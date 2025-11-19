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





-- ============================================================================
-- Universitätsbibliotheksverwaltungssystem - Umfangreiche Daten für DWH
-- Version 3.0 - Korrigiert für neues Schema (person_id als PK in Subtypen)
-- Hinweis: Diese Datei setzt eine leere Datenbank voraus
-- Zuerst bibliothek_schema_korrigiert_de.sql ausführen!
-- ============================================================================

-- ============================================================================
-- 1. KATEGORIEN (10 Kategorien)
-- ============================================================================

INSERT INTO KATEGORIE (kategoriename, beschreibung) VALUES
('Informatik', 'Bücher über Programmierung, Algorithmen, Datenstrukturen und Computerwissenschaften'),
('Mathematik', 'Mathematische Lehrbücher und Forschungsarbeiten'),
('Physik', 'Physik und verwandte Naturwissenschaften'),
('Ingenieurwesen', 'Technische und ingenieurwissenschaftliche Literatur'),
('Betriebswirtschaft', 'Management, Finanzen und Geschäftsliteratur'),
('Literatur', 'Belletristik, Romane und literarische Werke'),
('Geschichte', 'Historische Bücher und Biografien'),
('Philosophie', 'Philosophische Werke und Ethik'),
('Biologie', 'Biowissenschaften und Medizin'),
('Chemie', 'Chemie und verwandte Wissenschaften');

-- ============================================================================
-- 2. VERLAGE (20 Verlage)
-- ============================================================================

INSERT INTO VERLAG (verlagsname, land, webseite) VALUES
('Springer', 'Deutschland', 'www.springer.com'),
('Pearson', 'USA', 'www.pearson.com'),
('O''Reilly Media', 'USA', 'www.oreilly.com'),
('MIT Press', 'USA', 'mitpress.mit.edu'),
('Cambridge University Press', 'UK', 'www.cambridge.org'),
('Oxford University Press', 'UK', 'www.oup.com'),
('Wiley', 'USA', 'www.wiley.com'),
('McGraw-Hill', 'USA', 'www.mheducation.com'),
('Addison-Wesley', 'USA', 'www.pearson.com/addison-wesley'),
('Hanser Verlag', 'Deutschland', 'www.hanser-fachbuch.de'),
('Galileo Press', 'Deutschland', 'www.rheinwerk-verlag.de'),
('dpunkt.verlag', 'Deutschland', 'www.dpunkt.de'),
('Elsevier', 'Niederlande', 'www.elsevier.com'),
('Routledge', 'UK', 'www.routledge.com'),
('Penguin Random House', 'USA', 'www.penguinrandomhouse.com'),
('HarperCollins', 'USA', 'www.harpercollins.com'),
('Macmillan', 'UK', 'www.macmillan.com'),
('Packt Publishing', 'UK', 'www.packtpub.com'),
('Manning Publications', 'USA', 'www.manning.com'),
('No Starch Press', 'USA', 'nostarch.com');

-- ============================================================================
-- 3. AUTOREN (50 Autoren)
-- ============================================================================

INSERT INTO AUTOR (vorname, nachname, biografie, land) VALUES
-- Informatik-Autoren
('Donald', 'Knuth', 'Amerikanischer Informatiker, bekannt für The Art of Computer Programming', 'USA'),
('Brian', 'Kernighan', 'Kanadischer Informatiker, Co-Autor von The C Programming Language', 'Kanada'),
('Dennis', 'Ritchie', 'Amerikanischer Informatiker, Entwickler der Programmiersprache C', 'USA'),
('Bjarne', 'Stroustrup', 'Dänischer Informatiker, Entwickler von C++', 'Dänemark'),
('Martin', 'Fowler', 'Britischer Softwareentwickler und Autor', 'UK'),
('Robert', 'Martin', 'Amerikanischer Softwareentwickler, bekannt als Uncle Bob', 'USA'),
('Joshua', 'Bloch', 'Amerikanischer Softwareingenieur, ehemaliger Google-Mitarbeiter', 'USA'),
('Erich', 'Gamma', 'Schweizer Informatiker, Co-Autor von Design Patterns', 'Schweiz'),
('Kent', 'Beck', 'Amerikanischer Softwareingenieur, Erfinder von Extreme Programming', 'USA'),
('Andrew', 'Tanenbaum', 'Amerikanisch-niederländischer Informatiker', 'Niederlande'),

-- Mathematik-Autoren
('Gilbert', 'Strang', 'Amerikanischer Mathematiker, MIT-Professor', 'USA'),
('James', 'Stewart', 'Kanadischer Mathematiker, bekannt für Calculus-Lehrbücher', 'Kanada'),
('Michael', 'Spivak', 'Amerikanischer Mathematiker', 'USA'),
('George', 'Simmons', 'Amerikanischer Mathematiker', 'USA'),
('Serge', 'Lang', 'Französisch-amerikanischer Mathematiker', 'USA'),

-- Physik-Autoren
('Richard', 'Feynman', 'Amerikanischer theoretischer Physiker, Nobelpreisträger', 'USA'),
('Leonard', 'Susskind', 'Amerikanischer theoretischer Physiker', 'USA'),
('Stephen', 'Hawking', 'Britischer theoretischer Physiker', 'UK'),
('Roger', 'Penrose', 'Britischer Mathematiker und Physiker', 'UK'),
('Brian', 'Greene', 'Amerikanischer theoretischer Physiker', 'USA'),

-- Ingenieurwesen-Autoren
('Frederick', 'Brooks', 'Amerikanischer Softwareingenieur, Autor von The Mythical Man-Month', 'USA'),
('Gene', 'Kim', 'Amerikanischer Autor und Forscher', 'USA'),
('Grady', 'Booch', 'Amerikanischer Softwareingenieur', 'USA'),
('Craig', 'Larman', 'Kanadischer Softwareingenieur', 'Kanada'),
('Ivar', 'Jacobson', 'Schwedischer Softwareingenieur', 'Schweden'),

-- Betriebswirtschaft-Autoren
('Peter', 'Drucker', 'Österreichisch-amerikanischer Managementberater', 'USA'),
('Michael', 'Porter', 'Amerikanischer Ökonom', 'USA'),
('Clayton', 'Christensen', 'Amerikanischer Betriebswirt', 'USA'),
('Philip', 'Kotler', 'Amerikanischer Marketing-Autor', 'USA'),
('Gary', 'Hamel', 'Amerikanischer Management-Autor', 'USA'),

-- Literatur-Autoren
('George', 'Orwell', 'Britischer Schriftsteller', 'UK'),
('Aldous', 'Huxley', 'Britischer Schriftsteller', 'UK'),
('Ray', 'Bradbury', 'Amerikanischer Science-Fiction-Autor', 'USA'),
('Isaac', 'Asimov', 'Russisch-amerikanischer Science-Fiction-Autor', 'USA'),
('Arthur', 'Clarke', 'Britischer Science-Fiction-Autor', 'UK'),

-- Geschichte-Autoren
('Yuval', 'Harari', 'Israelischer Historiker', 'Israel'),
('Jared', 'Diamond', 'Amerikanischer Geograph und Historiker', 'USA'),
('Barbara', 'Tuchman', 'Amerikanische Historikerin', 'USA'),
('Simon', 'Schama', 'Britischer Historiker', 'UK'),
('Eric', 'Hobsbawm', 'Britischer Historiker', 'UK'),

-- Philosophie-Autoren
('Daniel', 'Dennett', 'Amerikanischer Philosoph', 'USA'),
('Martha', 'Nussbaum', 'Amerikanische Philosophin', 'USA'),
('Alain', 'Badiou', 'Französischer Philosoph', 'Frankreich'),
('Slavoj', 'Žižek', 'Slowenischer Philosoph', 'Slowenien'),
('Judith', 'Butler', 'Amerikanische Philosophin', 'USA'),

-- Biologie-Autoren
('Richard', 'Dawkins', 'Britischer Biologe', 'UK'),
('Edward', 'Wilson', 'Amerikanischer Biologe', 'USA'),
('Stephen', 'Gould', 'Amerikanischer Paläontologe', 'USA'),
('Lynn', 'Margulis', 'Amerikanische Biologin', 'USA'),
('James', 'Watson', 'Amerikanischer Molekularbiologe', 'USA');

-- ============================================================================
-- 4. BÜCHER (100 Bücher)
-- ============================================================================

INSERT INTO BUCH (isbn, titel, erscheinungsjahr, auflage, kategorie_id, verlag_id) VALUES
-- Informatik (25 Bücher)
('9780262033848', 'Introduction to Algorithms', 2009, '3. Auflage', 1, 4),
('9780201896831', 'The Art of Computer Programming Vol. 1', 1997, '3. Auflage', 1, 9),
('9780134685991', 'Effective Java', 2018, '3. Auflage', 1, 9),
('9780132350884', 'Clean Code', 2008, '1. Auflage', 1, 2),
('9780201633610', 'Design Patterns', 1994, '1. Auflage', 1, 9),
('9780137081073', 'The Clean Coder', 2011, '1. Auflage', 1, 2),
('9780596007126', 'Head First Design Patterns', 2004, '1. Auflage', 1, 3),
('9781449355739', 'Learning Python', 2013, '5. Auflage', 1, 3),
('9781491950296', 'Programming Python', 2010, '4. Auflage', 1, 3),
('9780134190440', 'The Go Programming Language', 2015, '1. Auflage', 1, 9),
('9780596517748', 'JavaScript: The Good Parts', 2008, '1. Auflage', 1, 3),
('9781593279509', 'Eloquent JavaScript', 2018, '3. Auflage', 1, 20),
('9780134757599', 'Refactoring', 2018, '2. Auflage', 1, 9),
('9781449337711', 'Designing Data-Intensive Applications', 2017, '1. Auflage', 1, 3),
('9780136291558', 'Object-Oriented Software Construction', 1997, '2. Auflage', 1, 2),
('9780735619678', 'Code Complete', 2004, '2. Auflage', 1, 8),
('9781617294945', 'Spring in Action', 2018, '5. Auflage', 1, 19),
('9781491954249', 'Database Internals', 2019, '1. Auflage', 1, 3),
('9780596009205', 'Head First Java', 2005, '2. Auflage', 1, 3),
('9780135974445', 'Artificial Intelligence: A Modern Approach', 2020, '4. Auflage', 1, 2),
('9780262046305', 'Deep Learning', 2016, '1. Auflage', 1, 4),
('9781449369415', 'Python for Data Analysis', 2017, '2. Auflage', 1, 3),
('9783836245630', 'Java ist auch eine Insel', 2020, '15. Auflage', 1, 11),
('9780135166307', 'Computer Networks', 2020, '6. Auflage', 1, 2),
('9781118063330', 'Operating System Concepts', 2018, '10. Auflage', 1, 7),

-- Mathematik (15 Bücher)
('9780980232776', 'Linear Algebra and Its Applications', 2016, '5. Auflage', 2, 7),
('9780470458365', 'Calculus', 2015, '8. Auflage', 2, 7),
('9780521867061', 'Calculus on Manifolds', 2006, '1. Auflage', 2, 5),
('9780070576421', 'Differential Equations', 2016, '4. Auflage', 2, 8),
('9780486458335', 'Introduction to Real Analysis', 1997, '3. Auflage', 2, 8),
('9783642558856', 'Analysis 1', 2016, '12. Auflage', 2, 1),
('9783642558863', 'Analysis 2', 2016, '9. Auflage', 2, 1),
('9783540416289', 'Lineare Algebra', 2018, '18. Auflage', 2, 1),
('9780691140346', 'Introduction to Mathematical Statistics', 2013, '8. Auflage', 2, 8),
('9780471755333', 'Discrete Mathematics', 2006, '7. Auflage', 2, 7),
('9780486458243', 'Number Theory', 2008, '2. Auflage', 2, 8),
('9780521558259', 'Graph Theory', 2008, '4. Auflage', 2, 5),
('9783540761778', 'Topology', 2017, '3. Auflage', 2, 1),
('9780387984032', 'Complex Analysis', 2003, '3. Auflage', 2, 1),
('9780201314526', 'Concrete Mathematics', 1994, '2. Auflage', 2, 9),

-- Physik (12 Bücher)
('9780465025275', 'The Feynman Lectures on Physics', 2010, 'Neue Millennium Auflage', 3, 9),
('9780201021189', 'Gravitation', 1973, '1. Auflage', 3, 7),
('9780465062904', 'The Theoretical Minimum', 2013, '1. Auflage', 3, 9),
('9780553380163', 'A Brief History of Time', 1998, 'Aktualisierte Auflage', 3, 15),
('9780679776314', 'The Elegant Universe', 2003, '1. Auflage', 3, 15),
('9783110393217', 'Theoretische Physik 1: Mechanik', 2018, '12. Auflage', 3, 1),
('9783110393224', 'Theoretische Physik 2: Elektrodynamik', 2018, '11. Auflage', 3, 1),
('9783110393231', 'Theoretische Physik 3: Quantenmechanik', 2018, '10. Auflage', 3, 1),
('9780471879558', 'Introduction to Quantum Mechanics', 2004, '2. Auflage', 3, 7),
('9780521575072', 'Classical Mechanics', 2002, '3. Auflage', 3, 5),
('9780486652412', 'Statistical Mechanics', 1996, '3. Auflage', 3, 8),
('9780521429498', 'Relativity: Special, General, and Cosmological', 2004, '1. Auflage', 3, 5),

-- Ingenieurwesen (10 Bücher)
('9780201835953', 'The Mythical Man-Month', 1995, 'Jubiläumsausgabe', 4, 9),
('9781942788003', 'The Phoenix Project', 2013, '1. Auflage', 4, 2),
('9781942788294', 'The DevOps Handbook', 2016, '1. Auflage', 4, 2),
('9780321125217', 'Domain-Driven Design', 2003, '1. Auflage', 4, 9),
('9780134494166', 'Clean Architecture', 2017, '1. Auflage', 4, 2),
('9781617294747', 'Microservices Patterns', 2018, '1. Auflage', 4, 19),
('9783446459304', 'Softwarearchitektur', 2020, '1. Auflage', 4, 10),
('9780131177055', 'Working Effectively with Legacy Code', 2004, '1. Auflage', 4, 2),
('9781118031964', 'The Art of Software Testing', 2011, '3. Auflage', 4, 7),
('9781449363321', 'Site Reliability Engineering', 2016, '1. Auflage', 4, 3),

-- Betriebswirtschaft (10 Bücher)
('9780060555665', 'The Effective Executive', 2006, 'Überarbeitete Auflage', 5, 16),
('9780743269513', 'Competitive Strategy', 2004, '1. Auflage', 5, 16),
('9781633691780', 'Competing Against Luck', 2016, '1. Auflage', 5, 16),
('9780132390026', 'Marketing Management', 2015, '15. Auflage', 5, 2),
('9781591843023', 'Leading the Revolution', 2002, '1. Auflage', 5, 16),
('9783800653508', 'Marketing', 2018, '13. Auflage', 5, 13),
('9783791041964', 'Grundlagen der Unternehmensführung', 2019, '6. Auflage', 5, 13),
('9783658037291', 'Strategisches Management', 2017, '9. Auflage', 5, 1),
('9783406715150', 'Projektmanagement', 2020, '12. Auflage', 5, 13),
('9783800651528', 'Personalmanagement', 2019, '10. Auflage', 5, 13),

-- Literatur (10 Bücher)
('9780451524935', '1984', 1961, 'Taschenbuchausgabe', 6, 15),
('9780060850524', 'Brave New World', 2006, 'Neuauflage', 6, 16),
('9781451673319', 'Fahrenheit 451', 2012, '60. Jubiläum', 6, 16),
('9780553293357', 'Foundation', 1991, 'Neuauflage', 6, 15),
('9780345391803', '2001: A Space Odyssey', 1968, '1. Auflage', 6, 15),
('9783423136402', 'Der Steppenwolf', 2012, 'Neuausgabe', 6, 12),
('9783518371916', 'Der Prozess', 1998, 'Studienausgabe', 6, 12),
('9783442736447', 'Die Verwandlung', 2010, 'Taschenbuch', 6, 12),
('9783150183656', 'Faust', 2018, 'Reclam', 6, 12),
('9783423140010', 'Buddenbrooks', 2012, 'Neuausgabe', 6, 12),

-- Geschichte (8 Bücher)
('9780062316097', 'Sapiens', 2015, '1. Auflage', 7, 16),
('9780062316110', 'Homo Deus', 2017, '1. Auflage', 7, 16),
('9780393354324', 'Guns, Germs, and Steel', 2005, 'Neuauflage', 7, 17),
('9780812968453', 'The Guns of August', 1994, 'Neuausgabe', 7, 15),
('9783406739774', 'Die Deutschen und ihre Geschichte', 2020, '4. Auflage', 7, 5),
('9783406734670', 'Europa im Mittelalter', 2019, '3. Auflage', 7, 5),
('9783406740534', 'Geschichte des 20. Jahrhunderts', 2020, '2. Auflage', 7, 5),
('9783406619601', 'Weltgeschichte', 2018, '1. Auflage', 7, 5),

-- Philosophie (6 Bücher)
('9780140455649', 'Consciousness Explained', 1993, '1. Auflage', 8, 15),
('9780199669035', 'Upheavals of Thought', 2003, '1. Auflage', 8, 6),
('9781784785451', 'Being and Event', 2013, 'Englische Ausgabe', 8, 14),
('9783518296257', 'Die Grenzen der Interpretation', 1992, '1. Auflage', 8, 12),
('9783518295359', 'Subjekt und Macht', 2005, '1. Auflage', 8, 12),
('9783518587034', 'Das Unbehagen an der Kultur', 2009, 'Studienausgabe', 8, 12),

-- Biologie (4 Bücher)
('9780199291151', 'The Selfish Gene', 2006, '30. Jubiläum', 9, 6),
('9780674454903', 'On Human Nature', 2004, 'Überarbeitete Auflage', 9, 6),
('9780393315738', 'Wonderful Life', 2007, 'Neuauflage', 9, 17),
('9783827427922', 'Lehrbuch der Molekularbiologie', 2015, '4. Auflage', 9, 1);

-- ============================================================================
-- 5. BUCH_AUTOR Beziehungen
-- ============================================================================

INSERT INTO BUCH_AUTOR (buch_id, autor_id) VALUES
-- Informatik
(1, 1), (2, 1), (3, 7), (4, 6), (5, 8), (6, 6), (7, 8), (8, 3), (9, 3), (10, 2),
(11, 3), (12, 3), (13, 5), (14, 5), (15, 6), (16, 6), (17, 7), (18, 9), (19, 7),
(20, 10), (21, 10), (22, 10), (23, 2), (24, 10), (25, 10),
-- Mathematik
(26, 11), (27, 12), (28, 13), (29, 14), (30, 15), (31, 11), (32, 11), (33, 11),
(34, 12), (35, 14), (36, 15), (37, 14), (38, 13), (39, 13), (40, 1),
-- Physik
(41, 16), (42, 16), (43, 17), (44, 18), (45, 20), (46, 16), (47, 16), (48, 16),
(49, 17), (50, 17), (51, 17), (52, 19),
-- Ingenieurwesen
(53, 21), (54, 22), (55, 22), (56, 23), (57, 6), (58, 24), (59, 23), (60, 6),
(61, 9), (62, 22),
-- Betriebswirtschaft
(63, 26), (64, 27), (65, 28), (66, 29), (67, 30), (68, 29), (69, 26), (70, 27),
(71, 28), (72, 27),
-- Literatur
(73, 31), (74, 32), (75, 33), (76, 34), (77, 35), (78, 31), (79, 31), (80, 32),
(81, 33), (82, 34),
-- Geschichte
(83, 36), (84, 36), (85, 37), (86, 38), (87, 39), (88, 40), (89, 39), (90, 38),
-- Philosophie
(91, 41), (92, 42), (93, 43), (94, 44), (95, 45), (96, 41),
-- Biologie
(97, 46), (98, 47), (99, 48), (100, 50);

-- ============================================================================
-- 6. BUCHEXEMPLAR (250 Exemplare - 2-3 pro Buch)
-- Die ersten 50 Einträge detailliert, Rest ähnlich wie in der originalen Datei
-- ============================================================================

INSERT INTO BUCHEXEMPLAR (buch_id, barcode, anschaffungsdatum, zustand, status) VALUES
-- Informatik Bücher 1-25 (je 2-3 Exemplare)
(1, 'BC001001', '2020-01-15', 'Gut', 'Verfügbar'),
(1, 'BC001002', '2020-01-15', 'Gut', 'Verfügbar'),
(1, 'BC001003', '2021-06-20', 'Neu', 'Verfügbar'),
(2, 'BC002001', '2019-08-10', 'Akzeptabel', 'Verfügbar'),
(2, 'BC002002', '2021-02-15', 'Gut', 'Verfügbar'),
(3, 'BC003001', '2020-05-01', 'Gut', 'Verfügbar'),
(3, 'BC003002', '2022-09-15', 'Neu', 'Verfügbar'),
(4, 'BC004001', '2020-03-10', 'Gut', 'Verfügbar'),
(4, 'BC004002', '2021-11-20', 'Neu', 'Verfügbar'),
(5, 'BC005001', '2019-11-05', 'Akzeptabel', 'Verfügbar'),
(5, 'BC005002', '2022-04-12', 'Gut', 'Verfügbar'),
(6, 'BC006001', '2020-06-15', 'Gut', 'Verfügbar'),
(6, 'BC006002', '2022-08-10', 'Neu', 'Verfügbar'),
(7, 'BC007001', '2020-02-20', 'Gut', 'Verfügbar'),
(7, 'BC007002', '2023-03-01', 'Neu', 'Verfügbar'),
(8, 'BC008001', '2020-09-10', 'Gut', 'Verfügbar'),
(8, 'BC008002', '2022-11-20', 'Neu', 'Verfügbar'),
(9, 'BC009001', '2020-07-25', 'Gut', 'Verfügbar'),
(9, 'BC009002', '2023-08-15', 'Neu', 'Verfügbar'),
(10, 'BC010001', '2021-03-10', 'Gut', 'Verfügbar'),
(10, 'BC010002', '2023-05-12', 'Neu', 'Verfügbar'),
(11, 'BC011001', '2020-04-15', 'Gut', 'Verfügbar'),
(11, 'BC011002', '2022-10-05', 'Neu', 'Verfügbar'),
(12, 'BC012001', '2021-01-20', 'Gut', 'Verfügbar'),
(12, 'BC012002', '2023-02-10', 'Neu', 'Verfügbar'),
(13, 'BC013001', '2020-08-05', 'Gut', 'Verfügbar'),
(13, 'BC013002', '2022-12-15', 'Neu', 'Verfügbar'),
(14, 'BC014001', '2021-05-20', 'Gut', 'Verfügbar'),
(14, 'BC014002', '2023-01-25', 'Neu', 'Verfügbar'),
(15, 'BC015001', '2020-11-10', 'Akzeptabel', 'Verfügbar'),
(15, 'BC015002', '2022-07-20', 'Gut', 'Verfügbar'),
(16, 'BC016001', '2020-02-25', 'Gut', 'Verfügbar'),
(16, 'BC016002', '2022-09-30', 'Neu', 'Verfügbar'),
(17, 'BC017001', '2021-06-15', 'Gut', 'Verfügbar'),
(17, 'BC017002', '2023-04-10', 'Neu', 'Verfügbar'),
(18, 'BC018001', '2021-02-10', 'Gut', 'Verfügbar'),
(18, 'BC018002', '2023-06-15', 'Neu', 'Verfügbar'),
(19, 'BC019001', '2020-09-20', 'Gut', 'Verfügbar'),
(19, 'BC019002', '2022-11-05', 'Neu', 'Verfügbar'),
(20, 'BC020001', '2021-07-15', 'Gut', 'Verfügbar'),
(20, 'BC020002', '2023-03-20', 'Neu', 'Verfügbar'),
(21, 'BC021001', '2021-04-10', 'Gut', 'Verfügbar'),
(21, 'BC021002', '2023-05-25', 'Neu', 'Verfügbar'),
(22, 'BC022001', '2021-08-20', 'Gut', 'Verfügbar'),
(22, 'BC022002', '2023-07-10', 'Neu', 'Verfügbar'),
(23, 'BC023001', '2021-01-05', 'Gut', 'Verfügbar'),
(23, 'BC023002', '2023-02-20', 'Neu', 'Verfügbar'),
(24, 'BC024001', '2021-09-15', 'Gut', 'Verfügbar'),
(24, 'BC024002', '2023-08-05', 'Neu', 'Verfügbar'),
(25, 'BC025001', '2021-03-25', 'Gut', 'Verfügbar'),
(25, 'BC025002', '2023-04-15', 'Neu', 'Verfügbar'),

-- Mathematik Bücher 26-40 (je 2 Exemplare)
(26, 'BC026001', '2020-01-20', 'Gut', 'Verfügbar'),
(26, 'BC026002', '2022-06-15', 'Neu', 'Verfügbar'),
(27, 'BC027001', '2020-02-15', 'Gut', 'Verfügbar'),
(27, 'BC027002', '2022-07-20', 'Neu', 'Verfügbar'),
(28, 'BC028001', '2020-03-10', 'Gut', 'Verfügbar'),
(28, 'BC028002', '2022-08-25', 'Neu', 'Verfügbar'),
(29, 'BC029001', '2020-04-05', 'Gut', 'Verfügbar'),
(29, 'BC029002', '2022-09-10', 'Neu', 'Verfügbar'),
(30, 'BC030001', '2020-05-20', 'Gut', 'Verfügbar'),
(30, 'BC030002', '2022-10-15', 'Neu', 'Verfügbar'),
(31, 'BC031001', '2020-06-15', 'Gut', 'Verfügbar'),
(31, 'BC031002', '2022-11-20', 'Neu', 'Verfügbar'),
(32, 'BC032001', '2020-07-10', 'Gut', 'Verfügbar'),
(32, 'BC032002', '2022-12-05', 'Neu', 'Verfügbar'),
(33, 'BC033001', '2020-08-25', 'Gut', 'Verfügbar'),
(33, 'BC033002', '2023-01-10', 'Neu', 'Verfügbar'),
(34, 'BC034001', '2020-09-20', 'Gut', 'Verfügbar'),
(34, 'BC034002', '2023-02-15', 'Neu', 'Verfügbar'),
(35, 'BC035001', '2020-10-15', 'Gut', 'Verfügbar'),
(35, 'BC035002', '2023-03-20', 'Neu', 'Verfügbar'),
(36, 'BC036001', '2020-11-10', 'Gut', 'Verfügbar'),
(36, 'BC036002', '2023-04-25', 'Neu', 'Verfügbar'),
(37, 'BC037001', '2020-12-05', 'Gut', 'Verfügbar'),
(37, 'BC037002', '2023-05-10', 'Neu', 'Verfügbar'),
(38, 'BC038001', '2021-01-20', 'Gut', 'Verfügbar'),
(38, 'BC038002', '2023-06-15', 'Neu', 'Verfügbar'),
(39, 'BC039001', '2021-02-15', 'Gut', 'Verfügbar'),
(39, 'BC039002', '2023-07-20', 'Neu', 'Verfügbar'),
(40, 'BC040001', '2021-03-10', 'Gut', 'Verfügbar'),
(40, 'BC040002', '2023-08-25', 'Neu', 'Verfügbar'),

-- Physik Bücher 41-52 (je 2 Exemplare)
(41, 'BC041001', '2020-01-15', 'Gut', 'Verfügbar'),
(41, 'BC041002', '2022-06-20', 'Neu', 'Verfügbar'),
(42, 'BC042001', '2020-02-20', 'Gut', 'Verfügbar'),
(42, 'BC042002', '2022-07-15', 'Neu', 'Verfügbar'),
(43, 'BC043001', '2020-03-15', 'Gut', 'Verfügbar'),
(43, 'BC043002', '2022-08-10', 'Neu', 'Verfügbar'),
(44, 'BC044001', '2020-04-10', 'Gut', 'Verfügbar'),
(44, 'BC044002', '2022-09-05', 'Neu', 'Verfügbar'),
(45, 'BC045001', '2020-05-05', 'Gut', 'Verfügbar'),
(45, 'BC045002', '2022-10-20', 'Neu', 'Verfügbar'),
(46, 'BC046001', '2020-06-20', 'Gut', 'Verfügbar'),
(46, 'BC046002', '2022-11-15', 'Neu', 'Verfügbar'),
(47, 'BC047001', '2020-07-15', 'Gut', 'Verfügbar'),
(47, 'BC047002', '2022-12-10', 'Neu', 'Verfügbar'),
(48, 'BC048001', '2020-08-10', 'Gut', 'Verfügbar'),
(48, 'BC048002', '2023-01-05', 'Neu', 'Verfügbar'),
(49, 'BC049001', '2020-09-05', 'Gut', 'Verfügbar'),
(49, 'BC049002', '2023-02-20', 'Neu', 'Verfügbar'),
(50, 'BC050001', '2020-10-20', 'Gut', 'Verfügbar'),
(50, 'BC050002', '2023-03-15', 'Neu', 'Verfügbar'),
(51, 'BC051001', '2020-11-15', 'Gut', 'Verfügbar'),
(51, 'BC051002', '2023-04-10', 'Neu', 'Verfügbar'),
(52, 'BC052001', '2020-12-10', 'Gut', 'Verfügbar'),
(52, 'BC052002', '2023-05-05', 'Neu', 'Verfügbar'),

-- Ingenieurwesen Bücher 53-62 (je 2 Exemplare)
(53, 'BC053001', '2020-01-10', 'Gut', 'Verfügbar'),
(53, 'BC053002', '2022-06-25', 'Neu', 'Verfügbar'),
(54, 'BC054001', '2020-02-25', 'Gut', 'Verfügbar'),
(54, 'BC054002', '2022-07-10', 'Neu', 'Verfügbar'),
(55, 'BC055001', '2020-03-20', 'Gut', 'Verfügbar'),
(55, 'BC055002', '2022-08-15', 'Neu', 'Verfügbar'),
(56, 'BC056001', '2020-04-15', 'Gut', 'Verfügbar'),
(56, 'BC056002', '2022-09-20', 'Neu', 'Verfügbar'),
(57, 'BC057001', '2020-05-10', 'Gut', 'Verfügbar'),
(57, 'BC057002', '2022-10-25', 'Neu', 'Verfügbar'),
(58, 'BC058001', '2020-06-05', 'Gut', 'Verfügbar'),
(58, 'BC058002', '2022-11-10', 'Neu', 'Verfügbar'),
(59, 'BC059001', '2020-07-20', 'Gut', 'Verfügbar'),
(59, 'BC059002', '2022-12-15', 'Neu', 'Verfügbar'),
(60, 'BC060001', '2020-08-15', 'Gut', 'Verfügbar'),
(60, 'BC060002', '2023-01-20', 'Neu', 'Verfügbar'),
(61, 'BC061001', '2020-09-10', 'Gut', 'Verfügbar'),
(61, 'BC061002', '2023-02-25', 'Neu', 'Verfügbar'),
(62, 'BC062001', '2020-10-05', 'Gut', 'Verfügbar'),
(62, 'BC062002', '2023-03-10', 'Neu', 'Verfügbar'),

-- Betriebswirtschaft Bücher 63-72 (je 2 Exemplare)
(63, 'BC063001', '2020-01-25', 'Gut', 'Verfügbar'),
(63, 'BC063002', '2022-06-10', 'Neu', 'Verfügbar'),
(64, 'BC064001', '2020-02-10', 'Gut', 'Verfügbar'),
(64, 'BC064002', '2022-07-25', 'Neu', 'Verfügbar'),
(65, 'BC065001', '2020-03-05', 'Gut', 'Verfügbar'),
(65, 'BC065002', '2022-08-20', 'Neu', 'Verfügbar'),
(66, 'BC066001', '2020-04-20', 'Gut', 'Verfügbar'),
(66, 'BC066002', '2022-09-15', 'Neu', 'Verfügbar'),
(67, 'BC067001', '2020-05-15', 'Gut', 'Verfügbar'),
(67, 'BC067002', '2022-10-10', 'Neu', 'Verfügbar'),
(68, 'BC068001', '2020-06-10', 'Gut', 'Verfügbar'),
(68, 'BC068002', '2022-11-25', 'Neu', 'Verfügbar'),
(69, 'BC069001', '2020-07-05', 'Gut', 'Verfügbar'),
(69, 'BC069002', '2022-12-20', 'Neu', 'Verfügbar'),
(70, 'BC070001', '2020-08-20', 'Gut', 'Verfügbar'),
(70, 'BC070002', '2023-01-15', 'Neu', 'Verfügbar'),
(71, 'BC071001', '2020-09-15', 'Gut', 'Verfügbar'),
(71, 'BC071002', '2023-02-10', 'Neu', 'Verfügbar'),
(72, 'BC072001', '2020-10-10', 'Gut', 'Verfügbar'),
(72, 'BC072002', '2023-03-05', 'Neu', 'Verfügbar'),

-- Literatur Bücher 73-82 (je 2-3 Exemplare)
(73, 'BC073001', '2019-01-15', 'Akzeptabel', 'Verfügbar'),
(73, 'BC073002', '2021-06-20', 'Gut', 'Verfügbar'),
(74, 'BC074001', '2019-02-10', 'Akzeptabel', 'Verfügbar'),
(74, 'BC074002', '2021-07-15', 'Gut', 'Verfügbar'),
(75, 'BC075001', '2019-03-05', 'Akzeptabel', 'Verfügbar'),
(75, 'BC075002', '2021-08-10', 'Gut', 'Verfügbar'),
(76, 'BC076001', '2019-04-20', 'Akzeptabel', 'Verfügbar'),
(76, 'BC076002', '2021-09-05', 'Gut', 'Verfügbar'),
(77, 'BC077001', '2019-05-15', 'Akzeptabel', 'Verfügbar'),
(77, 'BC077002', '2021-10-20', 'Gut', 'Verfügbar'),
(78, 'BC078001', '2019-06-10', 'Akzeptabel', 'Verfügbar'),
(78, 'BC078002', '2021-11-15', 'Gut', 'Verfügbar'),
(79, 'BC079001', '2019-07-05', 'Akzeptabel', 'Verfügbar'),
(79, 'BC079002', '2021-12-10', 'Gut', 'Verfügbar'),
(80, 'BC080001', '2019-08-20', 'Akzeptabel', 'Verfügbar'),
(80, 'BC080002', '2022-01-05', 'Gut', 'Verfügbar'),
(81, 'BC081001', '2019-09-15', 'Akzeptabel', 'Verfügbar'),
(81, 'BC081002', '2022-02-20', 'Gut', 'Verfügbar'),
(82, 'BC082001', '2019-10-10', 'Akzeptabel', 'Verfügbar'),
(82, 'BC082002', '2022-03-15', 'Gut', 'Verfügbar'),

-- Geschichte Bücher 83-90 (je 2 Exemplare)
(83, 'BC083001', '2020-01-05', 'Gut', 'Verfügbar'),
(83, 'BC083002', '2022-06-30', 'Neu', 'Verfügbar'),
(84, 'BC084001', '2020-02-20', 'Gut', 'Verfügbar'),
(84, 'BC084002', '2022-07-05', 'Neu', 'Verfügbar'),
(85, 'BC085001', '2020-03-25', 'Gut', 'Verfügbar'),
(85, 'BC085002', '2022-08-30', 'Neu', 'Verfügbar'),
(86, 'BC086001', '2020-04-10', 'Gut', 'Verfügbar'),
(86, 'BC086002', '2022-09-25', 'Neu', 'Verfügbar'),
(87, 'BC087001', '2020-05-25', 'Gut', 'Verfügbar'),
(87, 'BC087002', '2022-10-30', 'Neu', 'Verfügbar'),
(88, 'BC088001', '2020-06-30', 'Gut', 'Verfügbar'),
(88, 'BC088002', '2022-11-05', 'Neu', 'Verfügbar'),
(89, 'BC089001', '2020-07-25', 'Gut', 'Verfügbar'),
(89, 'BC089002', '2023-01-10', 'Neu', 'Verfügbar'),
(90, 'BC090001', '2020-08-05', 'Gut', 'Verfügbar'),
(90, 'BC090002', '2023-02-05', 'Neu', 'Verfügbar'),

-- Philosophie Bücher 91-96 (je 2 Exemplare)
(91, 'BC091001', '2020-01-30', 'Gut', 'Verfügbar'),
(91, 'BC091002', '2022-06-05', 'Neu', 'Verfügbar'),
(92, 'BC092001', '2020-02-05', 'Gut', 'Verfügbar'),
(92, 'BC092002', '2022-07-30', 'Neu', 'Verfügbar'),
(93, 'BC093001', '2020-03-30', 'Gut', 'Verfügbar'),
(93, 'BC093002', '2022-08-05', 'Neu', 'Verfügbar'),
(94, 'BC094001', '2020-04-25', 'Gut', 'Verfügbar'),
(94, 'BC094002', '2022-09-30', 'Neu', 'Verfügbar'),
(95, 'BC095001', '2020-05-30', 'Gut', 'Verfügbar'),
(95, 'BC095002', '2022-10-05', 'Neu', 'Verfügbar'),
(96, 'BC096001', '2020-06-25', 'Gut', 'Verfügbar'),
(96, 'BC096002', '2022-11-30', 'Neu', 'Verfügbar'),

-- Biologie Bücher 97-100 (je 2 Exemplare)
(97, 'BC097001', '2020-01-10', 'Gut', 'Verfügbar'),
(97, 'BC097002', '2022-06-15', 'Neu', 'Verfügbar'),
(98, 'BC098001', '2020-02-15', 'Gut', 'Verfügbar'),
(98, 'BC098002', '2022-07-20', 'Neu', 'Verfügbar'),
(99, 'BC099001', '2020-03-20', 'Gut', 'Verfügbar'),
(99, 'BC099002', '2022-08-25', 'Neu', 'Verfügbar'),
(100, 'BC100001', '2020-04-25', 'Gut', 'Verfügbar'),
(100, 'BC100002', '2022-09-10', 'Neu', 'Verfügbar');

-- ============================================================================
-- 7. PERSON (80 Personen: 70 Mitglieder + 10 Bibliothekare)
-- ============================================================================

INSERT INTO PERSON (vorname, nachname, email, telefon) VALUES
-- Studenten (50 Personen)
('Anna', 'Müller', 'anna.mueller@uni-example.de', '+49-30-12345601'),
('Max', 'Schmidt', 'max.schmidt@uni-example.de', '+49-30-12345602'),
('Sophie', 'Wagner', 'sophie.wagner@uni-example.de', '+49-30-12345603'),
('Leon', 'Becker', 'leon.becker@uni-example.de', '+49-30-12345604'),
('Emma', 'Hoffmann', 'emma.hoffmann@uni-example.de', '+49-30-12345605'),
('Paul', 'Schäfer', 'paul.schaefer@uni-example.de', '+49-30-12345606'),
('Mia', 'Koch', 'mia.koch@uni-example.de', '+49-30-12345607'),
('Jonas', 'Bauer', 'jonas.bauer@uni-example.de', '+49-30-12345608'),
('Laura', 'Richter', 'laura.richter@uni-example.de', '+49-30-12345609'),
('Felix', 'Klein', 'felix.klein@uni-example.de', '+49-30-12345610'),
('Hannah', 'Wolf', 'hannah.wolf@uni-example.de', '+49-30-12345611'),
('Tim', 'Schröder', 'tim.schroeder@uni-example.de', '+49-30-12345612'),
('Lena', 'Neumann', 'lena.neumann@uni-example.de', '+49-30-12345613'),
('Lukas', 'Schwarz', 'lukas.schwarz@uni-example.de', '+49-30-12345614'),
('Lea', 'Zimmermann', 'lea.zimmermann@uni-example.de', '+49-30-12345615'),
('Tobias', 'Krüger', 'tobias.krueger@uni-example.de', '+49-30-12345616'),
('Sarah', 'Hartmann', 'sarah.hartmann@uni-example.de', '+49-30-12345617'),
('Niklas', 'Schmitt', 'niklas.schmitt@uni-example.de', '+49-30-12345618'),
('Julia', 'Werner', 'julia.werner@uni-example.de', '+49-30-12345619'),
('David', 'Meyer', 'david.meyer@uni-example.de', '+49-30-12345620'),
('Lisa', 'Weber', 'lisa.weber@uni-example.de', '+49-30-12345621'),
('Moritz', 'Schulz', 'moritz.schulz@uni-example.de', '+49-30-12345622'),
('Jana', 'Fischer', 'jana.fischer@uni-example.de', '+49-30-12345623'),
('Simon', 'Lehmann', 'simon.lehmann@uni-example.de', '+49-30-12345624'),
('Amelie', 'Lang', 'amelie.lang@uni-example.de', '+49-30-12345625'),
('Daniel', 'Roth', 'daniel.roth@uni-example.de', '+49-30-12345626'),
('Jessica', 'Baumann', 'jessica.baumann@uni-example.de', '+49-30-12345627'),
('Sebastian', 'Scholz', 'sebastian.scholz@uni-example.de', '+49-30-12345628'),
('Vanessa', 'Hermann', 'vanessa.hermann@uni-example.de', '+49-30-12345629'),
('Christian', 'Kühn', 'christian.kuehn@uni-example.de', '+49-30-12345630'),
('Michelle', 'Engel', 'michelle.engel@uni-example.de', '+49-30-12345631'),
('Markus', 'Heinrich', 'markus.heinrich@uni-example.de', '+49-30-12345632'),
('Stefanie', 'Lorenz', 'stefanie.lorenz@uni-example.de', '+49-30-12345633'),
('Patrick', 'Ritter', 'patrick.ritter@uni-example.de', '+49-30-12345634'),
('Melanie', 'Groß', 'melanie.gross@uni-example.de', '+49-30-12345635'),
('Dominik', 'Walter', 'dominik.walter@uni-example.de', '+49-30-12345636'),
('Katharina', 'Berger', 'katharina.berger@uni-example.de', '+49-30-12345637'),
('Alexander', 'Sommer', 'alexander.sommer@uni-example.de', '+49-30-12345638'),
('Nicole', 'Albrecht', 'nicole.albrecht@uni-example.de', '+49-30-12345639'),
('Benjamin', 'Braun', 'benjamin.braun@uni-example.de', '+49-30-12345640'),
('Tobias', 'Arnold', 'tobias.arnold@uni-example.de', '+49-30-12345641'),
('Sandra', 'Bauer', 'sandra.bauer@uni-example.de', '+49-30-12345642'),
('Oliver', 'König', 'oliver.koenig@uni-example.de', '+49-30-12345643'),
('Jasmin', 'Pohl', 'jasmin.pohl@uni-example.de', '+49-30-12345644'),
('Marco', 'Böhm', 'marco.boehm@uni-example.de', '+49-30-12345645'),
('Tanja', 'Friedrich', 'tanja.friedrich@uni-example.de', '+49-30-12345646'),
('Philipp', 'Krause', 'philipp.krause@uni-example.de', '+49-30-12345647'),
('Andrea', 'Schuster', 'andrea.schuster@uni-example.de', '+49-30-12345648'),
('Stefan', 'Horn', 'stefan.horn@uni-example.de', '+49-30-12345649'),
('Nadine', 'Vogt', 'nadine.vogt@uni-example.de', '+49-30-12345650'),

-- Dozenten (10 Personen)
('Prof. Dr. Thomas', 'Bergmann', 'thomas.bergmann@uni-example.de', '+49-30-12345701'),
('Prof. Dr. Maria', 'Schneider', 'maria.schneider@uni-example.de', '+49-30-12345702'),
('Dr. Michael', 'Keller', 'michael.keller@uni-example.de', '+49-30-12345703'),
('Dr. Sabine', 'Peters', 'sabine.peters@uni-example.de', '+49-30-12345704'),
('Prof. Dr. Andreas', 'Frank', 'andreas.frank@uni-example.de', '+49-30-12345705'),
('Dr. Christina', 'Möller', 'christina.moeller@uni-example.de', '+49-30-12345706'),
('Prof. Dr. Robert', 'Kaiser', 'robert.kaiser@uni-example.de', '+49-30-12345707'),
('Dr. Kathrin', 'Jung', 'kathrin.jung@uni-example.de', '+49-30-12345708'),
('Prof. Dr. Martin', 'Fuchs', 'martin.fuchs@uni-example.de', '+49-30-12345709'),
('Dr. Sandra', 'Vogel', 'sandra.vogel@uni-example.de', '+49-30-12345710'),

-- Personal (10 Personen)
('Peter', 'Hoffmeister', 'peter.hoffmeister@uni-example.de', '+49-30-12345801'),
('Sabrina', 'Kaufmann', 'sabrina.kaufmann@uni-example.de', '+49-30-12345802'),
('Thomas', 'Winkler', 'thomas.winkler@uni-example.de', '+49-30-12345803'),
('Martina', 'Krause', 'martina.krause@uni-example.de', '+49-30-12345804'),
('Frank', 'Schumacher', 'frank.schumacher@uni-example.de', '+49-30-12345805'),
('Andrea', 'Vogel', 'andrea.vogel@uni-example.de', '+49-30-12345806'),
('Klaus', 'Huber', 'klaus.huber@uni-example.de', '+49-30-12345807'),
('Petra', 'Dietrich', 'petra.dietrich@uni-example.de', '+49-30-12345808'),
('Ralf', 'Ziegler', 'ralf.ziegler@uni-example.de', '+49-30-12345809'),
('Birgit', 'Kuhn', 'birgit.kuhn@uni-example.de', '+49-30-12345810'),

-- Bibliothekare (10 Personen)
('Claudia', 'Fischer', 'claudia.fischer@bib-example.de', '+49-30-12346001'),
('Jürgen', 'Maier', 'juergen.maier@bib-example.de', '+49-30-12346002'),
('Susanne', 'Schulze', 'susanne.schulze@bib-example.de', '+49-30-12346003'),
('Werner', 'König', 'werner.koenig@bib-example.de', '+49-30-12346004'),
('Monika', 'Becker', 'monika.becker@bib-example.de', '+49-30-12346005'),
('Rainer', 'Braun', 'rainer.braun@bib-example.de', '+49-30-12346006'),
('Gabriele', 'Lange', 'gabriele.lange@bib-example.de', '+49-30-12346007'),
('Dieter', 'Zimmermann', 'dieter.zimmermann@bib-example.de', '+49-30-12346008'),
('Ute', 'Schmid', 'ute.schmid@bib-example.de', '+49-30-12346009'),
('Harald', 'Richter', 'harald.richter@bib-example.de', '+49-30-12346010');

-- ============================================================================
-- 8. MITGLIED (70 Mitglieder) - KORREKTUR: person_id als PK
-- ============================================================================

INSERT INTO MITGLIED (person_id, mitgliedstyp, registrierungsdatum, status) VALUES
-- Studenten (50)
(1, 'Student', '2022-09-15', 'Aktiv'),
(2, 'Student', '2022-09-20', 'Aktiv'),
(3, 'Student', '2022-10-01', 'Aktiv'),
(4, 'Student', '2022-10-10', 'Aktiv'),
(5, 'Student', '2022-10-15', 'Aktiv'),
(6, 'Student', '2023-03-01', 'Aktiv'),
(7, 'Student', '2023-03-15', 'Aktiv'),
(8, 'Student', '2023-04-01', 'Aktiv'),
(9, 'Student', '2023-04-20', 'Aktiv'),
(10, 'Student', '2023-09-01', 'Aktiv'),
(11, 'Student', '2023-09-10', 'Aktiv'),
(12, 'Student', '2023-09-15', 'Aktiv'),
(13, 'Student', '2023-10-01', 'Aktiv'),
(14, 'Student', '2023-10-10', 'Aktiv'),
(15, 'Student', '2023-10-20', 'Aktiv'),
(16, 'Student', '2024-03-01', 'Aktiv'),
(17, 'Student', '2024-03-10', 'Aktiv'),
(18, 'Student', '2024-03-20', 'Aktiv'),
(19, 'Student', '2024-04-01', 'Aktiv'),
(20, 'Student', '2024-04-15', 'Aktiv'),
(21, 'Student', '2024-09-01', 'Aktiv'),
(22, 'Student', '2024-09-05', 'Aktiv'),
(23, 'Student', '2024-09-10', 'Aktiv'),
(24, 'Student', '2024-09-15', 'Aktiv'),
(25, 'Student', '2024-10-01', 'Aktiv'),
(26, 'Student', '2023-01-15', 'Aktiv'),
(27, 'Student', '2023-02-01', 'Aktiv'),
(28, 'Student', '2023-02-15', 'Aktiv'),
(29, 'Student', '2023-05-01', 'Aktiv'),
(30, 'Student', '2023-06-01', 'Aktiv'),
(31, 'Student', '2023-07-01', 'Aktiv'),
(32, 'Student', '2023-08-15', 'Aktiv'),
(33, 'Student', '2024-01-10', 'Aktiv'),
(34, 'Student', '2024-02-01', 'Aktiv'),
(35, 'Student', '2024-02-15', 'Aktiv'),
(36, 'Student', '2024-05-01', 'Aktiv'),
(37, 'Student', '2024-06-01', 'Aktiv'),
(38, 'Student', '2024-07-01', 'Aktiv'),
(39, 'Student', '2024-08-01', 'Aktiv'),
(40, 'Student', '2024-10-15', 'Aktiv'),
(41, 'Student', '2023-09-01', 'Inaktiv'),
(42, 'Student', '2023-09-05', 'Aktiv'),
(43, 'Student', '2024-03-01', 'Aktiv'),
(44, 'Student', '2024-04-01', 'Gesperrt'),
(45, 'Student', '2024-05-01', 'Aktiv'),
(46, 'Student', '2024-06-01', 'Aktiv'),
(47, 'Student', '2024-07-01', 'Aktiv'),
(48, 'Student', '2024-08-01', 'Aktiv'),
(49, 'Student', '2024-09-01', 'Aktiv'),
(50, 'Student', '2024-10-01', 'Aktiv'),

-- Dozenten (10)
(51, 'Dozent', '2020-01-15', 'Aktiv'),
(52, 'Dozent', '2019-08-01', 'Aktiv'),
(53, 'Dozent', '2021-03-01', 'Aktiv'),
(54, 'Dozent', '2020-09-01', 'Aktiv'),
(55, 'Dozent', '2018-02-01', 'Aktiv'),
(56, 'Dozent', '2021-09-01', 'Aktiv'),
(57, 'Dozent', '2019-03-01', 'Aktiv'),
(58, 'Dozent', '2022-01-15', 'Aktiv'),
(59, 'Dozent', '2020-06-01', 'Aktiv'),
(60, 'Dozent', '2021-01-01', 'Aktiv'),

-- Personal (10)
(61, 'Personal', '2018-05-01', 'Aktiv'),
(62, 'Personal', '2019-07-01', 'Aktiv'),
(63, 'Personal', '2020-02-15', 'Aktiv'),
(64, 'Personal', '2021-06-01', 'Aktiv'),
(65, 'Personal', '2019-11-01', 'Aktiv'),
(66, 'Personal', '2022-01-15', 'Aktiv'),
(67, 'Personal', '2020-08-01', 'Aktiv'),
(68, 'Personal', '2021-03-01', 'Aktiv'),
(69, 'Personal', '2023-01-15', 'Aktiv'),
(70, 'Personal', '2022-09-01', 'Aktiv');

-- ============================================================================
-- 9. BIBLIOTHEKAR (10 Bibliothekare) - KORREKTUR: person_id als PK
-- ============================================================================

INSERT INTO BIBLIOTHEKAR (person_id, einstellungsdatum) VALUES
(71, '2015-03-01'),
(72, '2016-07-15'),
(73, '2017-01-10'),
(74, '2017-09-01'),
(75, '2018-05-15'),
(76, '2019-02-01'),
(77, '2019-11-01'),
(78, '2020-06-15'),
(79, '2021-03-01'),
(80, '2022-01-10');

-- ============================================================================
-- 10. AUSLEIHEN - KORREKTUR: mitglied_person_id und bibliothekar_person_id
-- ============================================================================

-- Hinweis: Trigger temporär deaktivieren für historische Daten
PRAGMA foreign_keys = OFF;

-- Zurückgegebene Ausleihen - verkürzte Version (30 Einträge für Beispiel)
INSERT INTO AUSLEIHE (exemplar_id, mitglied_person_id, bibliothekar_person_id, ausleihdatum, fälligkeitsdatum, rückgabedatum, status, strafbetrag) VALUES
-- 2022 Ausleihen
(1, 1, 71, '2022-01-15', '2022-02-05', '2022-02-03', 'Zurückgegeben', 0.00),
(5, 2, 72, '2022-02-10', '2022-03-03', '2022-03-01', 'Zurückgegeben', 0.00),
(10, 3, 71, '2022-03-05', '2022-03-26', '2022-03-30', 'Zurückgegeben', 4.00),
(15, 4, 73, '2022-04-12', '2022-05-03', '2022-05-02', 'Zurückgegeben', 0.00),
(20, 5, 72, '2022-05-08', '2022-05-29', '2022-05-28', 'Zurückgegeben', 0.00),
(25, 6, 74, '2022-06-14', '2022-07-05', '2022-07-10', 'Zurückgegeben', 5.00),
(30, 7, 71, '2022-07-20', '2022-08-10', '2022-08-09', 'Zurückgegeben', 0.00),
(35, 8, 75, '2022-08-15', '2022-09-05', '2022-09-12', 'Zurückgegeben', 7.00),
(40, 9, 72, '2022-09-10', '2022-10-01', '2022-09-30', 'Zurückgegeben', 0.00),
(45, 10, 73, '2022-10-05', '2022-10-26', '2022-10-25', 'Zurückgegeben', 0.00),

-- 2023 Ausleihen
(2, 11, 71, '2023-01-10', '2023-01-31', '2023-01-30', 'Zurückgegeben', 0.00),
(6, 12, 72, '2023-02-14', '2023-03-07', '2023-03-05', 'Zurückgegeben', 0.00),
(11, 13, 73, '2023-03-20', '2023-04-10', '2023-04-15', 'Zurückgegeben', 5.00),
(16, 14, 74, '2023-04-25', '2023-05-16', '2023-05-14', 'Zurückgegeben', 0.00),
(21, 15, 75, '2023-05-30', '2023-06-20', '2023-06-18', 'Zurückgegeben', 0.00),
(26, 16, 71, '2023-06-05', '2023-06-26', '2023-06-30', 'Zurückgegeben', 4.00),
(31, 17, 72, '2023-07-10', '2023-07-31', '2023-07-29', 'Zurückgegeben', 0.00),
(36, 18, 73, '2023-08-15', '2023-09-05', '2023-09-03', 'Zurückgegeben', 0.00),
(41, 19, 74, '2023-09-20', '2023-10-11', '2023-10-15', 'Zurückgegeben', 4.00),
(46, 20, 75, '2023-10-25', '2023-11-15', '2023-11-14', 'Zurückgegeben', 0.00),

-- 2024 Ausleihen - Zurückgegeben
(3, 21, 71, '2024-01-08', '2024-01-29', '2024-01-27', 'Zurückgegeben', 0.00),
(7, 22, 72, '2024-02-12', '2024-03-04', '2024-03-02', 'Zurückgegeben', 0.00),
(12, 23, 73, '2024-03-18', '2024-04-08', '2024-04-05', 'Zurückgegeben', 0.00),
(17, 24, 74, '2024-04-22', '2024-05-13', '2024-05-20', 'Zurückgegeben', 7.00),
(22, 25, 75, '2024-05-27', '2024-06-17', '2024-06-15', 'Zurückgegeben', 0.00),
(27, 26, 71, '2024-06-03', '2024-06-24', '2024-06-22', 'Zurückgegeben', 0.00),
(32, 27, 72, '2024-07-08', '2024-07-29', '2024-08-02', 'Zurückgegeben', 4.00),
(37, 28, 73, '2024-08-12', '2024-09-02', '2024-08-31', 'Zurückgegeben', 0.00),
(42, 29, 74, '2024-09-16', '2024-10-07', '2024-10-05', 'Zurückgegeben', 0.00),
(47, 1, 75, '2024-01-20', '2024-02-10', '2024-02-08', 'Zurückgegeben', 0.00);

-- Aktive Ausleihen (30 Einträge - noch nicht zurückgegeben)
INSERT INTO AUSLEIHE (exemplar_id, mitglied_person_id, bibliothekar_person_id, ausleihdatum, fälligkeitsdatum, rückgabedatum, status, strafbetrag) VALUES
-- Pünktliche Ausleihen
(4, 22, 71, DATE('now', '-10 days'), DATE('now', '+11 days'), NULL, 'Ausgeliehen', 0.00),
(8, 23, 72, DATE('now', '-8 days'), DATE('now', '+13 days'), NULL, 'Ausgeliehen', 0.00),
(13, 24, 73, DATE('now', '-15 days'), DATE('now', '+6 days'), NULL, 'Ausgeliehen', 0.00),
(18, 25, 74, DATE('now', '-5 days'), DATE('now', '+16 days'), NULL, 'Ausgeliehen', 0.00),
(23, 26, 75, DATE('now', '-12 days'), DATE('now', '+9 days'), NULL, 'Ausgeliehen', 0.00),
(28, 27, 71, DATE('now', '-7 days'), DATE('now', '+14 days'), NULL, 'Ausgeliehen', 0.00),
(33, 28, 72, DATE('now', '-3 days'), DATE('now', '+18 days'), NULL, 'Ausgeliehen', 0.00),
(38, 29, 73, DATE('now', '-14 days'), DATE('now', '+7 days'), NULL, 'Ausgeliehen', 0.00),
(43, 30, 74, DATE('now', '-9 days'), DATE('now', '+12 days'), NULL, 'Ausgeliehen', 0.00),
(48, 31, 75, DATE('now', '-6 days'), DATE('now', '+15 days'), NULL, 'Ausgeliehen', 0.00),
(53, 32, 71, DATE('now', '-11 days'), DATE('now', '+10 days'), NULL, 'Ausgeliehen', 0.00),
(58, 33, 72, DATE('now', '-4 days'), DATE('now', '+17 days'), NULL, 'Ausgeliehen', 0.00),
(63, 34, 73, DATE('now', '-13 days'), DATE('now', '+8 days'), NULL, 'Ausgeliehen', 0.00),
(68, 35, 74, DATE('now', '-2 days'), DATE('now', '+19 days'), NULL, 'Ausgeliehen', 0.00),
(73, 36, 75, DATE('now', '-16 days'), DATE('now', '+5 days'), NULL, 'Ausgeliehen', 0.00),

-- Überfällige Ausleihen
(9, 1, 71, DATE('now', '-35 days'), DATE('now', '-14 days'), NULL, 'Überfällig', 14.00),
(14, 5, 72, DATE('now', '-40 days'), DATE('now', '-19 days'), NULL, 'Überfällig', 19.00),
(19, 8, 73, DATE('now', '-45 days'), DATE('now', '-24 days'), NULL, 'Überfällig', 24.00),
(24, 10, 74, DATE('now', '-30 days'), DATE('now', '-9 days'), NULL, 'Überfällig', 9.00),
(29, 12, 75, DATE('now', '-38 days'), DATE('now', '-17 days'), NULL, 'Überfällig', 17.00),
(34, 15, 71, DATE('now', '-42 days'), DATE('now', '-21 days'), NULL, 'Überfällig', 21.00),
(39, 18, 72, DATE('now', '-33 days'), DATE('now', '-12 days'), NULL, 'Überfällig', 12.00),
(44, 20, 73, DATE('now', '-36 days'), DATE('now', '-15 days'), NULL, 'Überfällig', 15.00),
(49, 2, 74, DATE('now', '-48 days'), DATE('now', '-27 days'), NULL, 'Überfällig', 27.00),
(54, 4, 75, DATE('now', '-31 days'), DATE('now', '-10 days'), NULL, 'Überfällig', 10.00),
(59, 6, 71, DATE('now', '-37 days'), DATE('now', '-16 days'), NULL, 'Überfällig', 16.00),
(64, 9, 72, DATE('now', '-44 days'), DATE('now', '-23 days'), NULL, 'Überfällig', 23.00),
(69, 11, 73, DATE('now', '-29 days'), DATE('now', '-8 days'), NULL, 'Überfällig', 8.00),
(74, 13, 74, DATE('now', '-41 days'), DATE('now', '-20 days'), NULL, 'Überfällig', 20.00),
(79, 16, 75, DATE('now', '-34 days'), DATE('now', '-13 days'), NULL, 'Überfällig', 13.00);

-- Buchexemplar-Status für aktive Ausleihen aktualisieren
UPDATE BUCHEXEMPLAR SET status = 'Ausgeliehen' WHERE exemplar_id IN (
4, 8, 13, 18, 23, 28, 33, 38, 43, 48, 53, 58, 63, 68, 73,
9, 14, 19, 24, 29, 34, 39, 44, 49, 54, 59, 64, 69, 74, 79
);

PRAGMA foreign_keys = ON;

-- ============================================================================
-- 11. RESERVIERUNGEN - KORREKTUR: mitglied_person_id
-- ============================================================================

INSERT INTO RESERVIERUNG (buch_id, mitglied_person_id, reservierungsdatum, status) VALUES
-- Aktive Reservierungen (25)
(1, 37, DATE('now', '-5 days'), 'Aktiv'),
(1, 38, DATE('now', '-3 days'), 'Aktiv'),
(3, 39, DATE('now', '-7 days'), 'Aktiv'),
(4, 40, DATE('now', '-10 days'), 'Aktiv'),
(4, 1, DATE('now', '-6 days'), 'Aktiv'),
(5, 2, DATE('now', '-12 days'), 'Aktiv'),
(6, 3, DATE('now', '-4 days'), 'Aktiv'),
(8, 4, DATE('now', '-8 days'), 'Aktiv'),
(10, 5, DATE('now', '-9 days'), 'Aktiv'),
(14, 6, DATE('now', '-2 days'), 'Aktiv'),
(21, 7, DATE('now', '-11 days'), 'Aktiv'),
(22, 8, DATE('now', '-1 days'), 'Aktiv'),
(25, 9, DATE('now', '-15 days'), 'Aktiv'),
(30, 10, DATE('now', '-6 days'), 'Aktiv'),
(35, 11, DATE('now', '-13 days'), 'Aktiv'),
(40, 12, DATE('now', '-3 days'), 'Aktiv'),
(45, 13, DATE('now', '-9 days'), 'Aktiv'),
(50, 14, DATE('now', '-7 days'), 'Aktiv'),
(55, 15, DATE('now', '-5 days'), 'Aktiv'),
(60, 16, DATE('now', '-14 days'), 'Aktiv'),
(66, 17, DATE('now', '-4 days'), 'Aktiv'),
(70, 18, DATE('now', '-8 days'), 'Aktiv'),
(75, 19, DATE('now', '-10 days'), 'Aktiv'),
(80, 20, DATE('now', '-2 days'), 'Aktiv'),
(85, 21, DATE('now', '-12 days'), 'Aktiv'),

-- Erfüllte Reservierungen (10)
(2, 22, DATE('now', '-25 days'), 'Erfüllt'),
(7, 23, DATE('now', '-30 days'), 'Erfüllt'),
(12, 24, DATE('now', '-22 days'), 'Erfüllt'),
(18, 25, DATE('now', '-28 days'), 'Erfüllt'),
(24, 26, DATE('now', '-35 days'), 'Erfüllt'),
(31, 27, DATE('now', '-20 days'), 'Erfüllt'),
(38, 28, DATE('now', '-26 days'), 'Erfüllt'),
(48, 29, DATE('now', '-32 days'), 'Erfüllt'),
(56, 30, DATE('now', '-24 days'), 'Erfüllt'),
(67, 31, DATE('now', '-29 days'), 'Erfüllt'),

-- Stornierte Reservierungen (3)
(15, 32, DATE('now', '-18 days'), 'Storniert'),
(42, 33, DATE('now', '-40 days'), 'Storniert'),
(88, 34, DATE('now', '-45 days'), 'Storniert'),

-- Abgelaufene Reservierungen (2)
(28, 35, DATE('now', '-60 days'), 'Abgelaufen'),
(63, 36, DATE('now', '-55 days'), 'Abgelaufen');

-- ============================================================================
-- ZUSAMMENFASSUNG
-- ============================================================================

SELECT '============================================' AS '';
SELECT 'Umfangreiche Bibliotheksdaten erfolgreich geladen' AS '';
SELECT 'Version 3.0 - Korrigiert für neues Schema' AS '';
SELECT '============================================' AS '';

SELECT 'Kategorien: ' || COUNT(*) FROM KATEGORIE;
SELECT 'Verlage: ' || COUNT(*) FROM VERLAG;
SELECT 'Autoren: ' || COUNT(*) FROM AUTOR;
SELECT 'Bücher (Titel): ' || COUNT(*) FROM BUCH;
SELECT 'Buch-Autor Zuordnungen: ' || COUNT(*) FROM BUCH_AUTOR;
SELECT 'Buchexemplare: ' || COUNT(*) FROM BUCHEXEMPLAR;
SELECT '  - Verfügbar: ' || COUNT(*) FROM BUCHEXEMPLAR WHERE status = 'Verfügbar';
SELECT '  - Ausgeliehen: ' || COUNT(*) FROM BUCHEXEMPLAR WHERE status = 'Ausgeliehen';
SELECT 'Personen: ' || COUNT(*) FROM PERSON;
SELECT 'Mitglieder: ' || COUNT(*) FROM MITGLIED;
SELECT '  - Studenten: ' || COUNT(*) FROM MITGLIED WHERE mitgliedstyp = 'Student';
SELECT '  - Dozenten: ' || COUNT(*) FROM MITGLIED WHERE mitgliedstyp = 'Dozent';
SELECT '  - Personal: ' || COUNT(*) FROM MITGLIED WHERE mitgliedstyp = 'Personal';
SELECT 'Bibliothekare: ' || COUNT(*) FROM BIBLIOTHEKAR;
SELECT 'Gesamtausleihen: ' || COUNT(*) FROM AUSLEIHE;
SELECT '  - Zurückgegeben: ' || COUNT(*) FROM AUSLEIHE WHERE status = 'Zurückgegeben';
SELECT '  - Aktiv (Ausgeliehen): ' || COUNT(*) FROM AUSLEIHE WHERE status = 'Ausgeliehen';
SELECT '  - Überfällig: ' || COUNT(*) FROM AUSLEIHE WHERE status = 'Überfällig';
SELECT 'Gesamtreservierungen: ' || COUNT(*) FROM RESERVIERUNG;
SELECT '  - Aktiv: ' || COUNT(*) FROM RESERVIERUNG WHERE status = 'Aktiv';
SELECT '  - Erfüllt: ' || COUNT(*) FROM RESERVIERUNG WHERE status = 'Erfüllt';

SELECT '============================================' AS '';
SELECT 'WICHTIG: Dieses Schema verwendet person_id als PK in Subtypen!' AS '';
SELECT '  ✓ MITGLIED.person_id ist Primary Key' AS '';
SELECT '  ✓ BIBLIOTHEKAR.person_id ist Primary Key' AS '';
SELECT '  ✓ AUSLEIHE verwendet mitglied_person_id und bibliothekar_person_id' AS '';
SELECT '  ✓ RESERVIERUNG verwendet mitglied_person_id' AS '';
SELECT '============================================' AS '';
SELECT 'Datenbank bereit für Data Warehouse Operationen!' AS '';
SELECT '============================================' AS '';

