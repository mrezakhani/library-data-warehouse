-- ============================================================================
-- Data Warehouse Schema für Bibliotheksverwaltungssystem
-- Zweck: Beantwortung von:
--   1. Ausleihtrends über Zeit nach Kategorie
--   5. Bedarfsanalyse für Buchanschaffungen (Reservierungen + Ausleihfrequenz)
-- ============================================================================

PRAGMA foreign_keys = ON;

-- Bestehende DWH-Tabellen löschen falls vorhanden
DROP TABLE IF EXISTS FACT_RESERVIERUNG;
DROP TABLE IF EXISTS FACT_AUSLEIHE;
DROP TABLE IF EXISTS DIM_MITGLIED;
DROP TABLE IF EXISTS DIM_BUCH;
DROP TABLE IF EXISTS DIM_ZEIT;

-- ============================================================================
-- DIMENSION: DIM_ZEIT
-- Zeitdimension mit Hierarchien (Jahr > Quartal > Monat > Tag)
-- ============================================================================

CREATE TABLE DIM_ZEIT (
    datum_key INTEGER PRIMARY KEY,              -- Surrogate Key im Format YYYYMMDD
    datum DATE NOT NULL UNIQUE,                 -- Tatsächliches Datum

    -- Jahr-Hierarchie
    jahr INTEGER NOT NULL,                      -- 2022, 2023, 2024

    -- Quartal-Hierarchie
    quartal INTEGER NOT NULL,                   -- 1, 2, 3, 4
    quartal_name VARCHAR(10) NOT NULL,          -- 'Q1', 'Q2', 'Q3', 'Q4'
    jahr_quartal VARCHAR(10) NOT NULL,          -- '2024-Q1'

    -- Monat-Hierarchie
    monat INTEGER NOT NULL,                     -- 1-12
    monat_name VARCHAR(20) NOT NULL,            -- 'Januar', 'Februar', etc.
    jahr_monat VARCHAR(10) NOT NULL,            -- '2024-01'

    -- Woche
    woche INTEGER NOT NULL,                     -- 1-53
    jahr_woche VARCHAR(10) NOT NULL,            -- '2024-W01'

    -- Tag
    tag_im_monat INTEGER NOT NULL,              -- 1-31
    tag_im_jahr INTEGER NOT NULL,               -- 1-366
    wochentag INTEGER NOT NULL,                 -- 1=Montag, 7=Sonntag
    wochentag_name VARCHAR(20) NOT NULL,        -- 'Montag', 'Dienstag', etc.

    -- Semester (für Universitätskontext)
    semester VARCHAR(20) NOT NULL,              -- 'WiSe 2023/24', 'SoSe 2024'

    -- Flags
    ist_wochenende BOOLEAN NOT NULL,            -- TRUE wenn Sa/So
    ist_feiertag BOOLEAN DEFAULT FALSE          -- Optional: deutsche Feiertage
);

CREATE INDEX idx_dim_zeit_datum ON DIM_ZEIT(datum);
CREATE INDEX idx_dim_zeit_jahr_monat ON DIM_ZEIT(jahr, monat);
CREATE INDEX idx_dim_zeit_semester ON DIM_ZEIT(semester);

-- ============================================================================
-- DIMENSION: DIM_BUCH
-- Buchdimension mit denormalisierten Kategorie-, Autor- und Verlagsinformationen
-- ============================================================================

CREATE TABLE DIM_BUCH (
    buch_key INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate Key

    -- Natural Key
    buch_id INTEGER NOT NULL,                    -- Business Key aus OLTP

    -- Buchinformationen
    isbn VARCHAR(13) NOT NULL,
    titel VARCHAR(200) NOT NULL,
    erscheinungsjahr INTEGER,
    auflage VARCHAR(50),

    -- Kategorie (denormalisiert)
    kategorie_id INTEGER NOT NULL,
    kategorie_name VARCHAR(50) NOT NULL,
    kategorie_beschreibung TEXT,

    -- Autor (denormalisiert, konkateniert bei mehreren Autoren)
    autor_name VARCHAR(500),                     -- 'Nachname, Vorname; Nachname2, Vorname2'
    hauptautor_nachname VARCHAR(50),             -- Für Sortierung

    -- Verlag (denormalisiert)
    verlag_id INTEGER NOT NULL,
    verlag_name VARCHAR(100) NOT NULL,
    verlag_land VARCHAR(50),

    -- Aggregierte Bestandsinformationen (Slowly Changing Dimension Type 1)
    anzahl_exemplare INTEGER DEFAULT 0,          -- Gesamtzahl Exemplare
    anzahl_verfuegbar INTEGER DEFAULT 0,         -- Aktuell verfügbar

    -- Metadaten
    gueltig_von DATE DEFAULT CURRENT_DATE,
    gueltig_bis DATE,
    ist_aktuell BOOLEAN DEFAULT TRUE,

    -- Eindeutigkeit
    UNIQUE(buch_id, ist_aktuell)
);

CREATE INDEX idx_dim_buch_buch_id ON DIM_BUCH(buch_id);
CREATE INDEX idx_dim_buch_kategorie ON DIM_BUCH(kategorie_name);
CREATE INDEX idx_dim_buch_isbn ON DIM_BUCH(isbn);
CREATE INDEX idx_dim_buch_aktuell ON DIM_BUCH(ist_aktuell);

-- ============================================================================
-- DIMENSION: DIM_MITGLIED
-- Mitgliederdimension mit Slowly Changing Dimension Type 2 für Status-Änderungen
-- ============================================================================

CREATE TABLE DIM_MITGLIED (
    mitglied_key INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate Key

    -- Natural Key
    person_id INTEGER NOT NULL,                      -- Business Key aus OLTP

    -- Mitgliederinformationen
    vorname VARCHAR(50) NOT NULL,
    nachname VARCHAR(50) NOT NULL,
    name_voll VARCHAR(100) NOT NULL,                 -- 'Nachname, Vorname'
    email VARCHAR(100) NOT NULL,

    -- Mitgliedstyp (für Segmentierung)
    mitgliedstyp VARCHAR(20) NOT NULL,               -- 'Student', 'Dozent', 'Personal'
    status VARCHAR(10) NOT NULL,                     -- 'Aktiv', 'Inaktiv', 'Gesperrt'
    registrierungsdatum DATE NOT NULL,

    -- SCD Type 2 Metadaten
    gueltig_von DATE DEFAULT CURRENT_DATE,
    gueltig_bis DATE,
    ist_aktuell BOOLEAN DEFAULT TRUE,

    -- Eindeutigkeit
    UNIQUE(person_id, gueltig_von)
);

CREATE INDEX idx_dim_mitglied_person_id ON DIM_MITGLIED(person_id);
CREATE INDEX idx_dim_mitglied_typ ON DIM_MITGLIED(mitgliedstyp);
CREATE INDEX idx_dim_mitglied_aktuell ON DIM_MITGLIED(ist_aktuell);

-- ============================================================================
-- FACT TABLE: FACT_AUSLEIHE
-- Ausleih-Faktentabelle (Transaction Fact Table)
-- Granularität: Eine Zeile pro Ausleihe
-- ============================================================================

CREATE TABLE FACT_AUSLEIHE (
    ausleihe_key INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate Key

    -- Dimensionen (Foreign Keys)
    datum_ausleihe_key INTEGER NOT NULL,             -- Ausleihdatum
    datum_faelligkeit_key INTEGER NOT NULL,          -- Fälligkeitsdatum
    datum_rueckgabe_key INTEGER,                     -- Rückgabedatum (NULL wenn nicht zurückgegeben)
    buch_key INTEGER NOT NULL,
    mitglied_key INTEGER NOT NULL,

    -- Degenerate Dimensions (Transaktions-IDs)
    ausleihe_id INTEGER NOT NULL,                    -- Business Key aus OLTP
    bibliothekar_person_id INTEGER NOT NULL,         -- Vereinfacht: nur ID

    -- Additiv messbare Fakten
    ausleihdauer_tage INTEGER,                       -- Tatsächliche Ausleihdauer (wenn zurückgegeben)
    ausleihdauer_soll_tage INTEGER NOT NULL,         -- Sollte Ausleihdauer (Fälligkeit - Ausleihe)
    strafbetrag DECIMAL(10,2) DEFAULT 0.00,

    -- Semi-additiv messbare Fakten
    tage_ueberfaellig INTEGER DEFAULT 0,             -- Tage über Fälligkeit (wenn überfällig)

    -- Nicht-additiv messbare Fakten (Flags)
    ist_zurueckgegeben BOOLEAN DEFAULT FALSE,
    ist_ueberfaellig BOOLEAN DEFAULT FALSE,
    ist_verspaetet BOOLEAN DEFAULT FALSE,            -- Zurückgegeben aber zu spät

    -- Status
    status VARCHAR(20) NOT NULL,                     -- 'Ausgeliehen', 'Zurückgegeben', 'Überfällig'

    -- Foreign Key Constraints
    FOREIGN KEY (datum_ausleihe_key) REFERENCES DIM_ZEIT(datum_key),
    FOREIGN KEY (datum_faelligkeit_key) REFERENCES DIM_ZEIT(datum_key),
    FOREIGN KEY (datum_rueckgabe_key) REFERENCES DIM_ZEIT(datum_key),
    FOREIGN KEY (buch_key) REFERENCES DIM_BUCH(buch_key),
    FOREIGN KEY (mitglied_key) REFERENCES DIM_MITGLIED(mitglied_key),

    -- Business Rules
    CHECK(strafbetrag >= 0),
    CHECK(tage_ueberfaellig >= 0)
);

CREATE INDEX idx_fact_ausleihe_datum_ausleihe ON FACT_AUSLEIHE(datum_ausleihe_key);
CREATE INDEX idx_fact_ausleihe_buch ON FACT_AUSLEIHE(buch_key);
CREATE INDEX idx_fact_ausleihe_mitglied ON FACT_AUSLEIHE(mitglied_key);
CREATE INDEX idx_fact_ausleihe_status ON FACT_AUSLEIHE(ist_zurueckgegeben, ist_ueberfaellig);

-- ============================================================================
-- FACT TABLE: FACT_RESERVIERUNG
-- Reservierungs-Faktentabelle (Accumulating Snapshot Fact Table)
-- Granularität: Eine Zeile pro Reservierung
-- ============================================================================

CREATE TABLE FACT_RESERVIERUNG (
    reservierung_key INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate Key

    -- Dimensionen (Foreign Keys)
    datum_reservierung_key INTEGER NOT NULL,             -- Reservierungsdatum
    datum_erfuellung_key INTEGER,                        -- Erfüllungsdatum (wenn erfüllt)
    buch_key INTEGER NOT NULL,
    mitglied_key INTEGER NOT NULL,

    -- Degenerate Dimensions
    reservierung_id INTEGER NOT NULL,                    -- Business Key aus OLTP

    -- Additiv messbare Fakten
    wartezeit_tage INTEGER,                              -- Tage zwischen Reservierung und Erfüllung

    -- Nicht-additiv messbare Fakten (Flags)
    ist_aktiv BOOLEAN DEFAULT TRUE,
    ist_erfuellt BOOLEAN DEFAULT FALSE,
    ist_storniert BOOLEAN DEFAULT FALSE,
    ist_abgelaufen BOOLEAN DEFAULT FALSE,

    -- Status
    status VARCHAR(20) NOT NULL,                         -- 'Aktiv', 'Erfüllt', 'Storniert', 'Abgelaufen'

    -- Foreign Key Constraints
    FOREIGN KEY (datum_reservierung_key) REFERENCES DIM_ZEIT(datum_key),
    FOREIGN KEY (datum_erfuellung_key) REFERENCES DIM_ZEIT(datum_key),
    FOREIGN KEY (buch_key) REFERENCES DIM_BUCH(buch_key),
    FOREIGN KEY (mitglied_key) REFERENCES DIM_MITGLIED(mitglied_key),

    -- Business Rules
    CHECK(wartezeit_tage >= 0 OR wartezeit_tage IS NULL)
);

CREATE INDEX idx_fact_reservierung_datum ON FACT_RESERVIERUNG(datum_reservierung_key);
CREATE INDEX idx_fact_reservierung_buch ON FACT_RESERVIERUNG(buch_key);
CREATE INDEX idx_fact_reservierung_mitglied ON FACT_RESERVIERUNG(mitglied_key);
CREATE INDEX idx_fact_reservierung_status ON FACT_RESERVIERUNG(ist_aktiv, ist_erfuellt);

-- ============================================================================
-- VIEWS FÜR ANALYSE
-- ============================================================================

-- View 1: Ausleihtrends nach Kategorie und Zeit (für Frage 1)
CREATE VIEW v_ausleihe_trends AS
SELECT
    z.jahr,
    z.quartal_name,
    z.monat_name,
    z.jahr_monat,
    z.semester,
    b.kategorie_name,
    b.kategorie_id,
    COUNT(*) AS anzahl_ausleihen,
    COUNT(CASE WHEN f.ist_ueberfaellig THEN 1 END) AS anzahl_ueberfaellig,
    ROUND(AVG(f.ausleihdauer_tage), 2) AS durchschnitt_ausleihdauer,
    ROUND(SUM(f.strafbetrag), 2) AS summe_strafgebuehren,
    ROUND(100.0 * COUNT(CASE WHEN f.ist_ueberfaellig THEN 1 END) / COUNT(*), 2) AS ueberfaellig_rate_prozent
FROM FACT_AUSLEIHE f
JOIN DIM_ZEIT z ON f.datum_ausleihe_key = z.datum_key
JOIN DIM_BUCH b ON f.buch_key = b.buch_key
GROUP BY z.jahr, z.quartal_name, z.monat_name, z.jahr_monat, z.semester, b.kategorie_name, b.kategorie_id;

-- View 2: Bedarfsanalyse für Buchanschaffungen (für Frage 5)
CREATE VIEW v_bedarfsanalyse AS
SELECT
    b.buch_id,
    b.isbn,
    b.titel,
    b.kategorie_name,
    b.autor_name,
    b.anzahl_exemplare,

    -- Ausleih-Metriken
    COUNT(DISTINCT fa.ausleihe_key) AS anzahl_ausleihen,
    ROUND(CAST(COUNT(DISTINCT fa.ausleihe_key) AS FLOAT) / NULLIF(b.anzahl_exemplare, 0), 2) AS ausleihen_pro_exemplar,

    -- Reservierungs-Metriken
    COUNT(DISTINCT fr.reservierung_key) AS anzahl_reservierungen,
    COUNT(DISTINCT CASE WHEN fr.ist_aktiv THEN fr.reservierung_key END) AS anzahl_aktive_reservierungen,

    -- Bedarfs-Score (höher = höherer Bedarf)
    ROUND(
        (CAST(COUNT(DISTINCT fr.reservierung_key) AS FLOAT) / NULLIF(b.anzahl_exemplare, 0)) * 10 +
        (CAST(COUNT(DISTINCT fa.ausleihe_key) AS FLOAT) / NULLIF(b.anzahl_exemplare, 0)) * 5,
    2) AS bedarfs_score,

    -- Empfehlung
    CASE
        WHEN COUNT(DISTINCT CASE WHEN fr.ist_aktiv THEN fr.reservierung_key END) > b.anzahl_exemplare
        THEN 'DRINGEND: Mehr Exemplare anschaffen'
        WHEN COUNT(DISTINCT fr.reservierung_key) > b.anzahl_exemplare * 0.5
        THEN 'EMPFOHLEN: Zusätzliche Exemplare erwägen'
        WHEN COUNT(DISTINCT fa.ausleihe_key) / NULLIF(b.anzahl_exemplare, 0) > 10
        THEN 'HINWEIS: Hohe Auslastung'
        ELSE 'OK: Ausreichend Exemplare'
    END AS empfehlung

FROM DIM_BUCH b
LEFT JOIN FACT_AUSLEIHE fa ON b.buch_key = fa.buch_key
LEFT JOIN FACT_RESERVIERUNG fr ON b.buch_key = fr.buch_key
WHERE b.ist_aktuell = TRUE
GROUP BY b.buch_id, b.isbn, b.titel, b.kategorie_name, b.autor_name, b.anzahl_exemplare
HAVING anzahl_ausleihen > 0 OR anzahl_reservierungen > 0
ORDER BY bedarfs_score DESC;

-- View 3: Monatsvergleich Year-over-Year (für Frage 1)
CREATE VIEW v_jahresvergleich AS
SELECT
    z.monat,
    z.monat_name,
    b.kategorie_name,
    z.jahr,
    COUNT(*) AS anzahl_ausleihen,
    ROUND(SUM(f.strafbetrag), 2) AS summe_strafgebuehren
FROM FACT_AUSLEIHE f
JOIN DIM_ZEIT z ON f.datum_ausleihe_key = z.datum_key
JOIN DIM_BUCH b ON f.buch_key = b.buch_key
GROUP BY z.monat, z.monat_name, b.kategorie_name, z.jahr
ORDER BY z.monat, b.kategorie_name, z.jahr;

-- ============================================================================
-- METADATEN UND DOKUMENTATION
-- ============================================================================

-- Tabelle für ETL-Logging (optional, aber empfohlen)
CREATE TABLE ETL_LOG (
    log_id INTEGER PRIMARY KEY AUTOINCREMENT,
    tabelle_name VARCHAR(50) NOT NULL,
    start_zeitpunkt DATETIME DEFAULT CURRENT_TIMESTAMP,
    ende_zeitpunkt DATETIME,
    anzahl_eingefuegt INTEGER DEFAULT 0,
    anzahl_aktualisiert INTEGER DEFAULT 0,
    anzahl_fehler INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'RUNNING',  -- 'RUNNING', 'SUCCESS', 'ERROR'
    fehlermeldung TEXT
);

-- ============================================================================
-- ZUSAMMENFASSUNG
-- ============================================================================

SELECT '============================================' AS '';
SELECT 'Data Warehouse Schema erfolgreich erstellt' AS '';
SELECT '============================================' AS '';
SELECT 'Dimensionen:' AS '';
SELECT '  - DIM_ZEIT (Zeit-Dimension mit Hierarchien)' AS '';
SELECT '  - DIM_BUCH (Buch-Dimension mit Kategorie, Autor, Verlag)' AS '';
SELECT '  - DIM_MITGLIED (Mitglieder-Dimension mit SCD Type 2)' AS '';
SELECT '' AS '';
SELECT 'Faktentabellen:' AS '';
SELECT '  - FACT_AUSLEIHE (Transaction Fact Table)' AS '';
SELECT '  - FACT_RESERVIERUNG (Accumulating Snapshot Fact Table)' AS '';
SELECT '' AS '';
SELECT 'Analytische Views:' AS '';
SELECT '  - v_ausleihe_trends (Frage 1: Ausleihtrends)' AS '';
SELECT '  - v_bedarfsanalyse (Frage 5: Anschaffungsbedarf)' AS '';
SELECT '  - v_jahresvergleich (Year-over-Year Analyse)' AS '';
SELECT '' AS '';
SELECT 'Beantwortet folgende Fragestellungen:' AS '';
SELECT '  1. Wie entwickeln sich Ausleihzahlen nach Kategorie über Zeit?' AS '';
SELECT '  5. Welche Bücher sollten angeschafft werden?' AS '';
SELECT '============================================' AS '';
