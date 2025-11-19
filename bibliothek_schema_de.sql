-- ============================================================================
-- Universitätsbibliotheksverwaltungssystem - SQLite Datenbankschema
-- Version: 3.0 (Korrigiert: Subtypen verwenden person_id als PK)
-- ============================================================================

-- Fremdschlüssel temporär deaktivieren für saubere Erstellung
PRAGMA foreign_keys = OFF;

-- Bestehende Views löschen falls vorhanden
DROP VIEW IF EXISTS v_aktive_reservierungen;
DROP VIEW IF EXISTS v_aktive_ausleihen;
DROP VIEW IF EXISTS v_buch_mit_autoren;
DROP VIEW IF EXISTS v_buch_details;
DROP VIEW IF EXISTS v_bibliothekare;
DROP VIEW IF EXISTS v_mitglieder;
DROP VIEW IF EXISTS v_person_details;

-- Bestehende Tabellen löschen falls vorhanden (in umgekehrter Reihenfolge der Abhängigkeiten)
DROP TABLE IF EXISTS AUSLEIHE;
DROP TABLE IF EXISTS RESERVIERUNG;
DROP TABLE IF EXISTS BUCH_AUTOR;
DROP TABLE IF EXISTS BUCHEXEMPLAR;
DROP TABLE IF EXISTS BUCH;
DROP TABLE IF EXISTS MITGLIED;
DROP TABLE IF EXISTS BIBLIOTHEKAR;
DROP TABLE IF EXISTS PERSON;
DROP TABLE IF EXISTS KATEGORIE;
DROP TABLE IF EXISTS VERLAG;
DROP TABLE IF EXISTS AUTOR;

-- Fremdschlüssel aktivieren
PRAGMA foreign_keys = ON;

-- ============================================================================
-- SUPERTYP: PERSON
-- Enthält gemeinsame Attribute von MITGLIED und BIBLIOTHEKAR
-- ============================================================================

CREATE TABLE PERSON (
    person_id INTEGER PRIMARY KEY AUTOINCREMENT,
    vorname VARCHAR(50) NOT NULL,
    nachname VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    telefon VARCHAR(20),

    -- Audit-Felder
    erstellt_am DATETIME DEFAULT CURRENT_TIMESTAMP,
    aktualisiert_am DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Index für schnellere E-Mail-Suche
CREATE INDEX idx_person_email ON PERSON(email);

-- ============================================================================
-- SUBTYP: MITGLIED (erbt von PERSON)
-- Repräsentiert Bibliotheksmitglieder (Studenten, Dozenten, Personal)
-- KORREKTUR: person_id ist jetzt Primary Key (keine separate mitglied_id)
-- ============================================================================

CREATE TABLE MITGLIED (
    person_id INTEGER PRIMARY KEY,
    mitgliedstyp VARCHAR(20) NOT NULL CHECK(mitgliedstyp IN ('Student', 'Dozent', 'Personal')),
    registrierungsdatum DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(10) NOT NULL DEFAULT 'Aktiv' CHECK(status IN ('Aktiv', 'Inaktiv', 'Gesperrt')),

    FOREIGN KEY (person_id) REFERENCES PERSON(person_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- Indizes für schnellere Status- und Typ-Abfragen
CREATE INDEX idx_mitglied_status ON MITGLIED(status);
CREATE INDEX idx_mitglied_typ ON MITGLIED(mitgliedstyp);

-- ============================================================================
-- SUBTYP: BIBLIOTHEKAR (erbt von PERSON)
-- Repräsentiert Bibliothekspersonal das Operationen verwaltet
-- KORREKTUR: person_id ist jetzt Primary Key (keine separate bibliothekar_id)
-- ============================================================================

CREATE TABLE BIBLIOTHEKAR (
    person_id INTEGER PRIMARY KEY,
    einstellungsdatum DATE NOT NULL,

    FOREIGN KEY (person_id) REFERENCES PERSON(person_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- ============================================================================
-- KATEGORIE
-- Buchkategorien/Genres
-- ============================================================================

CREATE TABLE KATEGORIE (
    kategorie_id INTEGER PRIMARY KEY AUTOINCREMENT,
    kategoriename VARCHAR(50) NOT NULL UNIQUE,
    beschreibung TEXT
);

-- ============================================================================
-- VERLAG
-- Buchverlage
-- ============================================================================

CREATE TABLE VERLAG (
    verlag_id INTEGER PRIMARY KEY AUTOINCREMENT,
    verlagsname VARCHAR(100) NOT NULL,
    land VARCHAR(50),
    webseite VARCHAR(100)
);

-- Index für Verlagsnamensuche
CREATE INDEX idx_verlag_name ON VERLAG(verlagsname);

-- ============================================================================
-- AUTOR
-- Buchautoren
-- ============================================================================

CREATE TABLE AUTOR (
    autor_id INTEGER PRIMARY KEY AUTOINCREMENT,
    vorname VARCHAR(50) NOT NULL,
    nachname VARCHAR(50) NOT NULL,
    biografie TEXT,
    land VARCHAR(50)
);

-- Index für Autorennamensuche
CREATE INDEX idx_autor_name ON AUTOR(nachname, vorname);

-- ============================================================================
-- BUCH (Buch-Metadaten)
-- Enthält Buchinformationen (NICHT physische Exemplare)
-- ============================================================================

CREATE TABLE BUCH (
    buch_id INTEGER PRIMARY KEY AUTOINCREMENT,
    isbn VARCHAR(13) NOT NULL UNIQUE,
    titel VARCHAR(200) NOT NULL,
    erscheinungsjahr INTEGER,
    auflage VARCHAR(50),
    kategorie_id INTEGER NOT NULL,
    verlag_id INTEGER NOT NULL,

    FOREIGN KEY (kategorie_id) REFERENCES KATEGORIE(kategorie_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (verlag_id) REFERENCES VERLAG(verlag_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CHECK(erscheinungsjahr > 1000 AND erscheinungsjahr <= 2100)
);

-- Indizes für schnellere Suchen
CREATE INDEX idx_buch_isbn ON BUCH(isbn);
CREATE INDEX idx_buch_titel ON BUCH(titel);
CREATE INDEX idx_buch_kategorie ON BUCH(kategorie_id);
CREATE INDEX idx_buch_verlag ON BUCH(verlag_id);

-- ============================================================================
-- BUCH_AUTOR (Brückentabelle für Viele-zu-Viele)
-- Verknüpft Bücher mit Autoren
-- ============================================================================

CREATE TABLE BUCH_AUTOR (
    buch_id INTEGER NOT NULL,
    autor_id INTEGER NOT NULL,

    PRIMARY KEY (buch_id, autor_id),

    FOREIGN KEY (buch_id) REFERENCES BUCH(buch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (autor_id) REFERENCES AUTOR(autor_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- ============================================================================
-- BUCHEXEMPLAR (Physische Buchexemplare)
-- Repräsentiert einzelne physische Buchexemplare
-- ============================================================================

CREATE TABLE BUCHEXEMPLAR (
    exemplar_id INTEGER PRIMARY KEY AUTOINCREMENT,
    buch_id INTEGER NOT NULL,
    barcode VARCHAR(50) NOT NULL UNIQUE,
    anschaffungsdatum DATE NOT NULL DEFAULT CURRENT_DATE,
    zustand VARCHAR(20) NOT NULL DEFAULT 'Neu'
        CHECK(zustand IN ('Neu', 'Gut', 'Akzeptabel', 'Schlecht', 'Beschädigt')),
    status VARCHAR(20) NOT NULL DEFAULT 'Verfügbar'
        CHECK(status IN ('Verfügbar', 'Ausgeliehen', 'Reserviert', 'Wartung', 'Verloren', 'Beschädigt')),

    FOREIGN KEY (buch_id) REFERENCES BUCH(buch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- Indizes für Bestandsverwaltung
CREATE INDEX idx_exemplar_buch ON BUCHEXEMPLAR(buch_id);
CREATE INDEX idx_exemplar_status ON BUCHEXEMPLAR(status);
CREATE INDEX idx_exemplar_barcode ON BUCHEXEMPLAR(barcode);

-- ============================================================================
-- AUSLEIHE
-- Verfolgt Buchausleihtransaktionen
-- KORREKTUR: mitglied_id und bibliothekar_id referenzieren jetzt direkt person_id
-- ============================================================================

CREATE TABLE AUSLEIHE (
    ausleihe_id INTEGER PRIMARY KEY AUTOINCREMENT,
    exemplar_id INTEGER NOT NULL,
    mitglied_person_id INTEGER NOT NULL,
    bibliothekar_person_id INTEGER NOT NULL,
    ausleihdatum DATE NOT NULL DEFAULT CURRENT_DATE,
    fälligkeitsdatum DATE NOT NULL,
    rückgabedatum DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Ausgeliehen'
        CHECK(status IN ('Ausgeliehen', 'Zurückgegeben', 'Überfällig')),
    strafbetrag DECIMAL(10,2) DEFAULT 0.00,

    FOREIGN KEY (exemplar_id) REFERENCES BUCHEXEMPLAR(exemplar_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (mitglied_person_id) REFERENCES MITGLIED(person_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    FOREIGN KEY (bibliothekar_person_id) REFERENCES BIBLIOTHEKAR(person_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CHECK(fälligkeitsdatum > ausleihdatum),
    CHECK(rückgabedatum IS NULL OR rückgabedatum >= ausleihdatum),
    CHECK(strafbetrag >= 0)
);

-- Indizes für Ausleih-Abfragen
CREATE INDEX idx_ausleihe_mitglied ON AUSLEIHE(mitglied_person_id);
CREATE INDEX idx_ausleihe_bibliothekar ON AUSLEIHE(bibliothekar_person_id);
CREATE INDEX idx_ausleihe_exemplar ON AUSLEIHE(exemplar_id);
CREATE INDEX idx_ausleihe_status ON AUSLEIHE(status);
CREATE INDEX idx_ausleihe_fälligkeitsdatum ON AUSLEIHE(fälligkeitsdatum);

-- ============================================================================
-- RESERVIERUNG
-- Verfolgt Buchreservierungen
-- KORREKTUR: mitglied_id referenziert jetzt direkt person_id
-- ============================================================================

CREATE TABLE RESERVIERUNG (
    reservierung_id INTEGER PRIMARY KEY AUTOINCREMENT,
    buch_id INTEGER NOT NULL,
    mitglied_person_id INTEGER NOT NULL,
    reservierungsdatum DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Aktiv'
        CHECK(status IN ('Aktiv', 'Erfüllt', 'Storniert', 'Abgelaufen')),

    FOREIGN KEY (buch_id) REFERENCES BUCH(buch_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    FOREIGN KEY (mitglied_person_id) REFERENCES MITGLIED(person_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- Indizes für Reservierungs-Abfragen
CREATE INDEX idx_reservierung_buch ON RESERVIERUNG(buch_id);
CREATE INDEX idx_reservierung_mitglied ON RESERVIERUNG(mitglied_person_id);
CREATE INDEX idx_reservierung_status ON RESERVIERUNG(status);

-- ============================================================================
-- TRIGGER
-- ============================================================================

-- Trigger zum Aktualisieren von PERSON.aktualisiert_am bei jeder Änderung
CREATE TRIGGER trg_person_aktualisiert_am
AFTER UPDATE ON PERSON
BEGIN
    UPDATE PERSON
    SET aktualisiert_am = CURRENT_TIMESTAMP
    WHERE person_id = NEW.person_id;
END;

-- Trigger um Ausleihe eines nicht verfügbaren Buchs zu verhindern
CREATE TRIGGER trg_ausleihe_verfügbarkeit_prüfen
BEFORE INSERT ON AUSLEIHE
BEGIN
    SELECT CASE
        WHEN (SELECT status FROM BUCHEXEMPLAR WHERE exemplar_id = NEW.exemplar_id) != 'Verfügbar'
        THEN RAISE(ABORT, 'Ausleihe nicht möglich: Buchexemplar ist nicht verfügbar')
    END;
END;

-- Trigger zum Aktualisieren des BUCHEXEMPLAR-Status bei Ausleihe-Erstellung
CREATE TRIGGER trg_ausleihe_exemplar_status_aktualisieren
AFTER INSERT ON AUSLEIHE
BEGIN
    UPDATE BUCHEXEMPLAR
    SET status = 'Ausgeliehen'
    WHERE exemplar_id = NEW.exemplar_id;
END;

-- Trigger zum Aktualisieren des BUCHEXEMPLAR-Status bei Rückgabe
CREATE TRIGGER trg_ausleihe_rückgabe_exemplar_status_aktualisieren
AFTER UPDATE OF rückgabedatum ON AUSLEIHE
WHEN NEW.rückgabedatum IS NOT NULL AND OLD.rückgabedatum IS NULL
BEGIN
    UPDATE BUCHEXEMPLAR
    SET status = 'Verfügbar'
    WHERE exemplar_id = NEW.exemplar_id;

    UPDATE AUSLEIHE
    SET status = 'Zurückgegeben'
    WHERE ausleihe_id = NEW.ausleihe_id;
END;

-- ============================================================================
-- VIEWS (ANSICHTEN)
-- ============================================================================

-- Ansicht: Vollständige Personeninformationen mit Rolle
CREATE VIEW v_person_details AS
SELECT
    p.person_id,
    p.vorname,
    p.nachname,
    p.email,
    p.telefon,
    CASE
        WHEN m.person_id IS NOT NULL THEN 'Mitglied'
        WHEN b.person_id IS NOT NULL THEN 'Bibliothekar'
        ELSE 'Unbekannt'
    END AS rolle,
    m.person_id AS mitglied_person_id,
    m.mitgliedstyp,
    m.status AS mitglied_status,
    b.person_id AS bibliothekar_person_id,
    b.einstellungsdatum
FROM PERSON p
LEFT JOIN MITGLIED m ON p.person_id = m.person_id
LEFT JOIN BIBLIOTHEKAR b ON p.person_id = b.person_id;

-- Ansicht: Vollständige Mitgliederinformationen (PERSON und MITGLIED verknüpft)
CREATE VIEW v_mitglieder AS
SELECT
    m.person_id,
    p.vorname,
    p.nachname,
    p.email,
    p.telefon,
    m.mitgliedstyp,
    m.registrierungsdatum,
    m.status
FROM MITGLIED m
JOIN PERSON p ON m.person_id = p.person_id;

-- Ansicht: Vollständige Bibliothekaren-Informationen (PERSON und BIBLIOTHEKAR verknüpft)
CREATE VIEW v_bibliothekare AS
SELECT
    b.person_id,
    p.vorname,
    p.nachname,
    p.email,
    p.telefon,
    b.einstellungsdatum
FROM BIBLIOTHEKAR b
JOIN PERSON p ON b.person_id = p.person_id;

-- Ansicht: Buchdetails mit Kategorie und Verlag
CREATE VIEW v_buch_details AS
SELECT
    b.buch_id,
    b.isbn,
    b.titel,
    b.erscheinungsjahr,
    b.auflage,
    k.kategoriename,
    v.verlagsname,
    v.land AS verlag_land,
    (SELECT COUNT(*) FROM BUCHEXEMPLAR be WHERE be.buch_id = b.buch_id) AS gesamtexemplare,
    (SELECT COUNT(*) FROM BUCHEXEMPLAR be WHERE be.buch_id = b.buch_id AND be.status = 'Verfügbar') AS verfügbare_exemplare
FROM BUCH b
JOIN KATEGORIE k ON b.kategorie_id = k.kategorie_id
JOIN VERLAG v ON b.verlag_id = v.verlag_id;

-- Ansicht: Buch mit Autoren (verkettet)
CREATE VIEW v_buch_mit_autoren AS
SELECT
    b.buch_id,
    b.isbn,
    b.titel,
    b.erscheinungsjahr,
    GROUP_CONCAT(a.vorname || ' ' || a.nachname, '; ') AS autoren
FROM BUCH b
LEFT JOIN BUCH_AUTOR ba ON b.buch_id = ba.buch_id
LEFT JOIN AUTOR a ON ba.autor_id = a.autor_id
GROUP BY b.buch_id, b.isbn, b.titel, b.erscheinungsjahr;

-- Ansicht: Aktive Ausleihen mit Details
CREATE VIEW v_aktive_ausleihen AS
SELECT
    a.ausleihe_id,
    a.ausleihdatum,
    a.fälligkeitsdatum,
    a.status,
    a.strafbetrag,
    m.person_id AS mitglied_person_id,
    p_mitglied.vorname || ' ' || p_mitglied.nachname AS mitglied_name,
    p_mitglied.email AS mitglied_email,
    be.exemplar_id,
    be.barcode,
    b.titel AS buch_titel,
    b.isbn,
    bib.person_id AS bibliothekar_person_id,
    p_bib.vorname || ' ' || p_bib.nachname AS bibliothekar_name,
    CASE
        WHEN a.rückgabedatum IS NULL AND a.fälligkeitsdatum < DATE('now') THEN 'Überfällig'
        WHEN a.rückgabedatum IS NULL THEN 'Ausgeliehen'
        ELSE 'Zurückgegeben'
    END AS aktueller_status,
    CASE
        WHEN a.rückgabedatum IS NULL AND a.fälligkeitsdatum < DATE('now')
        THEN CAST((JULIANDAY('now') - JULIANDAY(a.fälligkeitsdatum)) AS INTEGER)
        ELSE 0
    END AS tage_überfällig
FROM AUSLEIHE a
JOIN MITGLIED m ON a.mitglied_person_id = m.person_id
JOIN PERSON p_mitglied ON m.person_id = p_mitglied.person_id
JOIN BUCHEXEMPLAR be ON a.exemplar_id = be.exemplar_id
JOIN BUCH b ON be.buch_id = b.buch_id
JOIN BIBLIOTHEKAR bib ON a.bibliothekar_person_id = bib.person_id
JOIN PERSON p_bib ON bib.person_id = p_bib.person_id
WHERE a.rückgabedatum IS NULL;

-- Ansicht: Aktive Reservierungen
CREATE VIEW v_aktive_reservierungen AS
SELECT
    r.reservierung_id,
    r.reservierungsdatum,
    r.status,
    m.person_id AS mitglied_person_id,
    p.vorname || ' ' || p.nachname AS mitglied_name,
    p.email AS mitglied_email,
    b.buch_id,
    b.titel AS buch_titel,
    b.isbn,
    (SELECT COUNT(*) FROM BUCHEXEMPLAR be WHERE be.buch_id = b.buch_id AND be.status = 'Verfügbar') AS verfügbare_exemplare
FROM RESERVIERUNG r
JOIN MITGLIED m ON r.mitglied_person_id = m.person_id
JOIN PERSON p ON m.person_id = p.person_id
JOIN BUCH b ON r.buch_id = b.buch_id
WHERE r.status = 'Aktiv';

-- ============================================================================
-- ZUSAMMENFASSUNG
-- ============================================================================

-- Schema-Erstellungs-Zusammenfassung anzeigen
SELECT '============================================' AS '';
SELECT 'Bibliotheksverwaltungssystem-Schema erstellt' AS '';
SELECT 'Version 3.0 - Korrigiert (Subtypen nutzen person_id als PK)' AS '';
SELECT '============================================' AS '';
SELECT 'Gesamttabellen: 11' AS '';
SELECT '  - PERSON (Supertyp)' AS '';
SELECT '  - MITGLIED, BIBLIOTHEKAR (Subtypen mit person_id als PK)' AS '';
SELECT '  - BUCH, BUCHEXEMPLAR (Metadaten + Physisch)' AS '';
SELECT '  - AUTOR, KATEGORIE, VERLAG' AS '';
SELECT '  - BUCH_AUTOR (Brückentabelle)' AS '';
SELECT '  - AUSLEIHE, RESERVIERUNG (Transaktionen)' AS '';
SELECT '' AS '';
SELECT 'Gesamtansichten: 7' AS '';
SELECT 'Gesamttrigger: 4' AS '';
SELECT 'Gesamtindizes: 16' AS '';
SELECT '============================================' AS '';
SELECT 'WICHTIGE ÄNDERUNGEN:' AS '';
SELECT '  ✓ MITGLIED: person_id ist nun PK (kein mitglied_id mehr)' AS '';
SELECT '  ✓ BIBLIOTHEKAR: person_id ist nun PK (kein bibliothekar_id mehr)' AS '';
SELECT '  ✓ AUSLEIHE: verwendet mitglied_person_id und bibliothekar_person_id' AS '';
SELECT '  ✓ RESERVIERUNG: verwendet mitglied_person_id' AS '';
SELECT '============================================' AS '';
