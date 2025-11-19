# Slowly Changing Dimensions (SCD) - Konzept für DWH Bibliotheksverwaltung

## Überblick

Slowly Changing Dimensions (SCD) sind Dimensionen im Data Warehouse, deren Attribute sich im Laufe der Zeit ändern können. Je nach Geschäftsanforderung gibt es verschiedene Strategien, um mit diesen Änderungen umzugehen.

---

## SCD Type 0 - Keine Änderungen (Fixed/Passive)

### Konzept
Attribute dürfen **niemals geändert** werden. Einmal gespeicherte Werte bleiben für immer konstant.

### Wann verwenden?
- Für Attribute, die sich definitionsgemäß nicht ändern können
- Historische Fakten, die unveränderlich sind

### Bibliotheks-Beispiel: ISBN in DIM_BUCH

**Szenario:**
- ISBN-13: 978-3-16-148410-0 wird dem Buch "Der Herr der Ringe" zugeordnet
- Diese ISBN ist eine **eindeutige internationale Buchnummer** und kann sich niemals ändern

**Implementierung:**
```sql
CREATE TABLE DIM_BUCH (
    buch_id INTEGER PRIMARY KEY,
    isbn TEXT NOT NULL UNIQUE,  -- SCD Type 0: Niemals ändern
    titel TEXT,
    -- ...
);
```

**Was passiert bei Änderungsversuch?**
- ETL-Prozess erkennt Änderung bei ISBN
- **Ablehnung** oder Warnung ausgeben
- Falls ISBN falsch war: Neues Buch anlegen, altes als "fehlerhaft" markieren

**Beispiel:**
```
Vorher:  buch_id=1, isbn='978-3-16-148410-0'
Versuch: buch_id=1, isbn='978-3-16-999999-9'  ❌ BLOCKIERT
```

---

## SCD Type 1 - Überschreiben (Overwrite)

### Konzept
Bei Änderungen wird der **alte Wert überschrieben**. Keine Historie wird gespeichert. Der aktuelle Wert ist für alle historischen Analysen gültig.

### Wann verwenden?
- Fehlerkorrektur (Tippfehler)
- Attribute, bei denen historische Werte irrelevant sind
- Wenn Speicherplatz/Performance wichtiger als Historie

### Bibliotheks-Beispiel 1: Titel-Korrektur in DIM_BUCH

**Szenario:**
Ein Buch wurde mit Tippfehler erfasst:
- **Alt:** "Der Herrr der Ringe" (3x 'r')
- **Neu:** "Der Herr der Ringe" (2x 'r')

**Implementierung:**
```sql
UPDATE DIM_BUCH
SET titel = 'Der Herr der Ringe',
    standort = 'A-3-15'  -- Auch Standort kann sich ändern
WHERE buch_id = 1;
```

**Vorher:**
```
buch_id | titel                | standort | kategorie_name
--------|---------------------|----------|---------------
1       | Der Herrr der Ringe | A-2-10   | Fantasy
```

**Nachher:**
```
buch_id | titel              | standort | kategorie_name
--------|-------------------|----------|---------------
1       | Der Herr der Ringe | A-3-15   | Fantasy
```

**Auswirkung auf Analysen:**
- Alle historischen Ausleihen zeigen jetzt den **korrigierten** Titel
- Report "Top 10 Bücher 2023": Zeigt "Der Herr der Ringe" (korrekt), nicht die alte Schreibweise

### Bibliotheks-Beispiel 2: Standort-Änderung

**Szenario:**
Bücher werden innerhalb der Bibliothek umgeräumt:
- **Alt:** Standort "A-2-10" (2. Etage, Gang A, Regal 10)
- **Neu:** Standort "C-1-05" (1. Etage, Gang C, Regal 5)

**Warum Type 1?**
- Für Analysen ist nur der **aktuelle Standort** relevant
- Niemand fragt: "Wie viele Bücher wurden ausgeliehen, als sie in Regal A-2-10 standen?"
- Bibliotheksmitarbeiter brauchen den aktuellen Standort zum Finden des Buchs

---

## SCD Type 2 - Historisierung (Add New Row)

### Konzept
Bei Änderungen wird eine **neue Zeile** mit der neuen Version eingefügt. Die alte Version bleibt erhalten mit Gültigkeitszeitraum.

### Wann verwenden?
- Wenn historische Werte für Analysen wichtig sind
- Bei Attributen, die den Kontext historischer Facts ändern
- Wenn man "Point-in-Time"-Analysen durchführen muss

### Bibliotheks-Beispiel 1: Mitgliedschaftstyp in DIM_MITGLIED

**Szenario:**
Anna Schmidt upgradet ihre Mitgliedschaft:
- **Alt (2024-01-01 bis 2024-06-30):** Mitgliedschaftstyp "Standard" (max. 3 Bücher)
- **Neu (ab 2024-07-01):** Mitgliedschaftstyp "Premium" (max. 10 Bücher)

**Implementierung:**
```sql
-- 1. Alte Version auf "nicht mehr aktuell" setzen
UPDATE DIM_MITGLIED
SET gueltig_bis = '2024-06-30',
    ist_aktuell = 0
WHERE person_id = 123 AND ist_aktuell = 1;

-- 2. Neue Version einfügen
INSERT INTO DIM_MITGLIED (
    mitglied_id, person_id, vorname, nachname,
    mitgliedschaftstyp, gueltig_von, gueltig_bis, ist_aktuell
) VALUES (
    NULL, 123, 'Anna', 'Schmidt',
    'Premium', '2024-07-01', '9999-12-31', 1
);
```

**Ergebnis:**
```
mitglied_id | person_id | vorname | mitgliedschaftstyp | gueltig_von | gueltig_bis | ist_aktuell
------------|-----------|---------|-------------------|-------------|-------------|------------
501         | 123       | Anna    | Standard          | 2024-01-01  | 2024-06-30  | 0
502         | 123       | Anna    | Premium           | 2024-07-01  | 9999-12-31  | 1
```

**Auswirkung auf Analysen:**

**Query 1: Anzahl Ausleihen nach Mitgliedschaftstyp (Q1 2024)**
```sql
SELECT
    dm.mitgliedschaftstyp,
    COUNT(*) AS anzahl_ausleihen
FROM FACT_AUSLEIHE fa
JOIN DIM_MITGLIED dm ON fa.mitglied_id = dm.mitglied_id
JOIN DIM_ZEIT dz ON fa.ausleihdatum_id = dz.datum_id
WHERE dz.quartal = 1 AND dz.jahr = 2024
  AND dz.datum BETWEEN dm.gueltig_von AND dm.gueltig_bis  -- Wichtig!
GROUP BY dm.mitgliedschaftstyp;
```

**Ergebnis:**
```
mitgliedschaftstyp | anzahl_ausleihen
-------------------|------------------
Standard           | 15  (Annas Ausleihen Jan-Jun)
Premium            | 0   (Noch kein Premium in Q1)
```

**Query 2: Aktuelle Mitglieder-Anzahl nach Typ**
```sql
SELECT
    mitgliedschaftstyp,
    COUNT(*) AS anzahl_mitglieder
FROM DIM_MITGLIED
WHERE ist_aktuell = 1
GROUP BY mitgliedschaftstyp;
```

**Warum Type 2 für Mitgliedschaftstyp?**
✅ Korrekte historische Analysen: "Welcher Mitgliedschaftstyp leiht am meisten aus?"
✅ Trendbericht: "Wie viele Upgrades von Standard zu Premium gab es?"
✅ Lifecycle-Analyse: "Durchschnittliche Zeit bis zum Upgrade?"

### Bibliotheks-Beispiel 2: Adressänderung in DIM_MITGLIED

**Szenario:**
Mitglied zieht um:
- **Alt:** Stadt "Berlin", PLZ "10115"
- **Neu:** Stadt "München", PLZ "80331"

**Warum Type 2?**
- Regionale Analysen: "Welche Stadtteile leihen welche Buchkategorien?"
- Wenn Anna in Berlin wohnte (2023-2024) und Fantasy-Bücher lieh, sollte das Berlin zugeordnet werden
- Nach Umzug nach München (ab 2025): Neue Ausleihen werden München zugeordnet

**Beispiel-Analyse:**
```sql
-- Welche Stadtteile mögen Fantasy-Bücher?
SELECT
    dm.stadt,
    COUNT(*) AS anzahl_fantasy_ausleihen
FROM FACT_AUSLEIHE fa
JOIN DIM_MITGLIED dm ON fa.mitglied_id = dm.mitglied_id
JOIN DIM_BUCH db ON fa.buch_id = db.buch_id
WHERE db.kategorie_name = 'Fantasy'
GROUP BY dm.stadt;
```

**Ergebnis (korrekt durch Type 2):**
```
stadt   | anzahl_fantasy_ausleihen
--------|-------------------------
Berlin  | 25  (inkl. Annas alte Ausleihen)
München | 8   (inkl. Annas neue Ausleihen)
```

---

## SCD Type 3 - Vorheriger Wert (Previous Value)

### Konzept
Zusätzliches Feld speichert den **vorherigen Wert**. Begrenzte Historie (nur 1 vorheriger Wert).

### Wann verwenden?
- Wenn nur die letzte Änderung relevant ist
- "Vorher/Nachher"-Vergleiche
- Weniger komplex als Type 2

### Bibliotheks-Beispiel: Kategorie-Umklassifizierung in DIM_BUCH

**Szenario:**
Die Bibliothek überarbeitet ihr Kategoriesystem:
- **Alt:** "Belletristik" (zu breit)
- **Neu:** "Historischer Roman" (spezifischer)

**Implementierung:**
```sql
CREATE TABLE DIM_BUCH (
    buch_id INTEGER PRIMARY KEY,
    titel TEXT,
    kategorie_name TEXT,           -- Aktuelle Kategorie
    kategorie_name_vorher TEXT,    -- Vorherige Kategorie
    kategorie_geaendert_am DATE,   -- Wann geändert?
    -- ...
);

UPDATE DIM_BUCH
SET kategorie_name_vorher = kategorie_name,
    kategorie_name = 'Historischer Roman',
    kategorie_geaendert_am = CURRENT_DATE
WHERE buch_id = 42;
```

**Ergebnis:**
```
buch_id | titel              | kategorie_name      | kategorie_name_vorher | kategorie_geaendert_am
--------|-------------------|--------------------|-----------------------|----------------------
42      | Die Säulen der Erde| Historischer Roman | Belletristik          | 2024-07-15
```

**Verwendung:**
```sql
-- Analyse: Auswirkung der Kategorie-Änderung
SELECT
    kategorie_name_vorher AS alte_kategorie,
    kategorie_name AS neue_kategorie,
    COUNT(*) AS anzahl_buecher
FROM DIM_BUCH
WHERE kategorie_name_vorher IS NOT NULL
GROUP BY kategorie_name_vorher, kategorie_name;
```

**Limitation:**
- Nur **1 vorherige Änderung** gespeichert
- Bei mehrfachen Änderungen gehen ältere Werte verloren

---

## SCD Type 4 - History Table (Separate History)

### Konzept
**Zwei Tabellen:**
1. **Aktuelle Dimension** (nur aktuelle Werte)
2. **History-Tabelle** (alle historischen Versionen)

### Wann verwenden?
- Wenn Historie selten abgefragt wird
- Performance-Optimierung für aktuelle Daten
- Trennung von operativen und historischen Queries

### Bibliotheks-Beispiel: DIM_MITGLIED mit History

**Implementierung:**
```sql
-- Aktuelle Dimension (schnell, klein)
CREATE TABLE DIM_MITGLIED (
    mitglied_id INTEGER PRIMARY KEY,
    person_id INTEGER NOT NULL,
    vorname TEXT,
    nachname TEXT,
    email TEXT,
    mitgliedschaftstyp TEXT,
    mitglied_seit DATE
);

-- History-Tabelle (alle Änderungen)
CREATE TABLE DIM_MITGLIED_HISTORY (
    history_id INTEGER PRIMARY KEY AUTOINCREMENT,
    mitglied_id INTEGER NOT NULL,
    person_id INTEGER NOT NULL,
    vorname TEXT,
    nachname TEXT,
    email TEXT,
    mitgliedschaftstyp TEXT,
    gueltig_von DATE,
    gueltig_bis DATE,
    FOREIGN KEY (mitglied_id) REFERENCES DIM_MITGLIED(mitglied_id)
);
```

**Aktuelle Tabelle:**
```
mitglied_id | person_id | vorname | mitgliedschaftstyp
------------|-----------|---------|-------------------
502         | 123       | Anna    | Premium
```

**History-Tabelle:**
```
history_id | mitglied_id | person_id | vorname | mitgliedschaftstyp | gueltig_von | gueltig_bis
-----------|-------------|-----------|---------|-------------------|-------------|-------------
1          | 502         | 123       | Anna    | Standard          | 2024-01-01  | 2024-06-30
2          | 502         | 123       | Anna    | Premium           | 2024-07-01  | 9999-12-31
```

**Verwendung:**

**Aktuelle Daten (schnell):**
```sql
SELECT * FROM DIM_MITGLIED WHERE mitglied_id = 502;
```

**Historische Analyse (selten):**
```sql
SELECT * FROM DIM_MITGLIED_HISTORY
WHERE mitglied_id = 502
  AND '2024-03-15' BETWEEN gueltig_von AND gueltig_bis;
```

**Vorteil:**
- Aktuelle Queries sind sehr schnell (keine Historie im Weg)
- Historie bleibt verfügbar für Audits/Analysen

---

## SCD Type 6 - Hybrid (1 + 2 + 3)

### Konzept
Kombination aus Type 1, 2 und 3:
- **Type 2:** Neue Zeilen für Versionen
- **Type 3:** Zusätzliches Feld für vorherigen Wert
- **Type 1:** Aktueller Wert wird in **allen Zeilen** aktualisiert

### Bibliotheks-Beispiel: DIM_MITGLIED Hybrid

**Implementierung:**
```sql
CREATE TABLE DIM_MITGLIED (
    mitglied_id INTEGER PRIMARY KEY AUTOINCREMENT,
    person_id INTEGER NOT NULL,
    vorname TEXT,
    nachname TEXT,

    -- Type 2: Historische Versionen
    mitgliedschaftstyp_historisch TEXT,
    gueltig_von DATE,
    gueltig_bis DATE,
    ist_aktuell INTEGER,

    -- Type 3: Vorheriger Wert
    mitgliedschaftstyp_vorher TEXT,

    -- Type 1: Aktueller Wert (in ALLEN Zeilen gleich)
    mitgliedschaftstyp_aktuell TEXT
);
```

**Beispiel:**
Anna: Standard → Premium → Gold

```
mitglied_id | person_id | mitgliedschaftstyp_historisch | mitgliedschaftstyp_vorher | mitgliedschaftstyp_aktuell | gueltig_von | gueltig_bis | ist_aktuell
------------|-----------|------------------------------|--------------------------|---------------------------|-------------|-------------|------------
501         | 123       | Standard                      | NULL                      | Gold                       | 2024-01-01  | 2024-06-30  | 0
502         | 123       | Premium                       | Standard                  | Gold                       | 2024-07-01  | 2024-12-31  | 0
503         | 123       | Gold                          | Premium                   | Gold                       | 2025-01-01  | 9999-12-31  | 1
```

**Verwendung:**

**Query 1: Historische Analyse**
```sql
-- Was war Annas Status im März 2024?
SELECT mitgliedschaftstyp_historisch
FROM DIM_MITGLIED
WHERE person_id = 123
  AND '2024-03-15' BETWEEN gueltig_von AND gueltig_bis;
-- Ergebnis: Standard
```

**Query 2: Aktueller Status für ALLE historischen Records**
```sql
-- Alle Annas Ausleihen mit aktuellem Status anreichern
SELECT
    fa.ausleihdatum_id,
    dm.mitgliedschaftstyp_aktuell  -- Immer "Gold"
FROM FACT_AUSLEIHE fa
JOIN DIM_MITGLIED dm ON fa.mitglied_id = dm.mitglied_id;
```

**Vorteil:**
- Historische Analysen möglich (Type 2)
- Schneller Zugriff auf aktuellen Status (Type 1)
- Vorher/Nachher-Vergleich (Type 3)

---

## Entscheidungsmatrix für Bibliotheks-DWH

| Attribut                    | Tabelle        | SCD Type | Begründung                                                                 |
|-----------------------------|----------------|----------|---------------------------------------------------------------------------|
| **ISBN**                    | DIM_BUCH       | Type 0   | Unveränderlich per Definition                                             |
| **Erscheinungsjahr**        | DIM_BUCH       | Type 0   | Historisches Faktum, kann sich nicht ändern                               |
| **Titel**                   | DIM_BUCH       | Type 1   | Änderungen sind Fehlerkorrektur; aktueller Titel für alle Analysen ok    |
| **Standort**                | DIM_BUCH       | Type 1   | Nur aktueller Standort relevant für Mitarbeiter                           |
| **Kategorie**               | DIM_BUCH       | Type 1   | Umklassifizierung; neue Kategorie gilt rückwirkend                       |
| **Autor**                   | DIM_BUCH       | Type 1   | Änderungen sind Korrekturen (Schreibweise)                               |
| **Mitgliedschaftstyp**      | DIM_MITGLIED   | Type 2   | Historische Werte wichtig für Ausleih-Analysen                           |
| **Email**                   | DIM_MITGLIED   | Type 2   | Kontaktänderungen tracken für Kommunikations-Audits                      |
| **Adresse (Stadt, PLZ)**    | DIM_MITGLIED   | Type 2   | Wichtig für regionale Analysen                                           |
| **Vorname/Nachname**        | DIM_MITGLIED   | Type 1   | Änderungen selten (Heirat); aktueller Name ausreichend                   |
| **Datum**                   | DIM_ZEIT       | Type 0   | Zeitdimension ist unveränderlich                                         |

---

## Implementierung im Projekt

### Aktuelles Design (DWH_Schema.sql):

✅ **DIM_ZEIT:** Keine SCD (generierte Dimension, unveränderlich)
✅ **DIM_BUCH:** SCD Type 1 (Overwrite)
✅ **DIM_MITGLIED:** SCD Type 2 (Track History)

### ETL-Prozess für SCD Type 2 (DIM_MITGLIED):

```sql
-- 1. Neue Mitglieder einfügen
INSERT INTO DIM_MITGLIED (...)
SELECT ... FROM staging.MITGLIED
WHERE person_id NOT IN (SELECT person_id FROM DIM_MITGLIED WHERE ist_aktuell = 1);

-- 2. Geänderte Mitglieder erkennen
CREATE TEMP TABLE changed_members AS
SELECT s.*
FROM staging.MITGLIED s
JOIN DIM_MITGLIED d ON s.person_id = d.person_id
WHERE d.ist_aktuell = 1
  AND (s.mitgliedschaftstyp != d.mitgliedschaftstyp
       OR s.email != d.email
       OR s.stadt != d.stadt);

-- 3. Alte Version inaktiv setzen
UPDATE DIM_MITGLIED
SET gueltig_bis = CURRENT_DATE,
    ist_aktuell = 0
WHERE person_id IN (SELECT person_id FROM changed_members)
  AND ist_aktuell = 1;

-- 4. Neue Version einfügen
INSERT INTO DIM_MITGLIED (...)
SELECT
    NULL AS mitglied_id,
    person_id,
    ...,
    CURRENT_DATE AS gueltig_von,
    '9999-12-31' AS gueltig_bis,
    1 AS ist_aktuell
FROM changed_members;
```

---

## Fazit

**Für das Bibliotheks-DWH verwenden wir:**

1. **SCD Type 0:** Unveränderliche Felder (ISBN, Erscheinungsjahr)
2. **SCD Type 1:** Korrekturen und aktuell-relevante Felder (Titel, Standort)
3. **SCD Type 2:** Historisch wichtige Felder (Mitgliedschaftstyp, Adresse)

**Begründung:**
- **Type 2 bei DIM_MITGLIED:** Ermöglicht korrekte historische Analysen ("Welcher Mitgliedschaftstyp leiht am meisten?")
- **Type 1 bei DIM_BUCH:** Vereinfacht Modell, da Buch-Änderungen selten und meist Korrekturen
- **Keine Type 3/4/6:** Zu komplex für den Projekt-Umfang; Type 1+2 decken alle Anforderungen ab





 ✅ Alle SCD-Typen mit Bibliotheks-Beispielen:

  1. SCD Type 0 (Fixed) - ISBN, Erscheinungsjahr
  2. SCD Type 1 (Overwrite) - Titel-Korrektur, Standort-Änderung
  3. SCD Type 2 (History) - Mitgliedschaftstyp, Adressänderung
  4. SCD Type 3 (Previous Value) - Kategorie-Umklassifizierung
  5. SCD Type 4 (History Table) - Separater History-Storage
  6. SCD Type 6 (Hybrid) - Kombination aus 1+2+3

  ✅ Pro SCD-Typ:

  - Konzept-Erklärung
  - Wann verwenden?
  - Konkrete Bibliotheks-Szenarien
  - SQL-Implementierung
  - Vorher/Nachher-Beispiele
  - Auswirkung auf Analysen

  ✅ Entscheidungsmatrix:

  Eine Tabelle, die zeigt welches Attribut welchen SCD-Typ bekommt und warum

  ✅ ETL-Prozess:

  Code-Beispiele für SCD Type 2 Implementierung

  Die Begründung für Ihr Projekt:
  - DIM_MITGLIED = Type 2: Mitgliedschaftstyp-Änderungen müssen für historische Analysen nachvollziehbar sein
  - DIM_BUCH = Type 1: Bücher ändern sich selten, nur Korrekturen sind relevant