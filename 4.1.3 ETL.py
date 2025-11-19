"""
ETL-Prozess für Data Warehouse Bibliotheksverwaltung
Lädt Daten aus OLTP-Datenbank in DWH mit SCD-Unterstützung
"""

import sqlite3
from datetime import datetime, timedelta
import sys

# Datenbank-Pfade
OLTP_DB = 'bibliothek_oltp.db'
DWH_DB =  'bibliothek_dwh.db'

# ============================================================
# ETL Log Tabelle ein Record einfügen
# ============================================================
def log_etl(conn, tabelle, anzahl_eingefuegt, anzahl_aktualisiert=0, status='SUCCESS', fehler=None):
    """Loggt ETL-Prozess in ETL_LOG Tabelle"""
    cursor = conn.cursor()
    cursor.execute("""
        INSERT INTO ETL_LOG (tabelle_name, ende_zeitpunkt, anzahl_eingefuegt,
                            anzahl_aktualisiert, status, fehlermeldung)
        VALUES (?, CURRENT_TIMESTAMP, ?, ?, ?, ?)
    """, (tabelle, anzahl_eingefuegt, anzahl_aktualisiert, status, fehler))
    conn.commit()


# ============================================================
# Am Anfang des ETL-Prozesses alle DWH Tabellen leeren
# ============================================================
def truncate_tables(dwh_conn):
    """Leert alle DWH-Tabellen vor dem ETL-Prozess"""
    cursor = dwh_conn.cursor()

    print("Leere bestehende DWH-Tabellen...")
    cursor.execute("DELETE FROM FACT_RESERVIERUNG")
    cursor.execute("DELETE FROM FACT_AUSLEIHE")
    cursor.execute("DELETE FROM DIM_MITGLIED")
    cursor.execute("DELETE FROM DIM_BUCH")
    cursor.execute("DELETE FROM DIM_ZEIT")
    dwh_conn.commit()
    print("✓ Tabellen geleert")
# ============================================================
# ETL: DIM_ZEIT (Generierte Dimension)
# ============================================================
def etl_dim_zeit(dwh_conn, start_year=2020, end_year=2027):
    """
    ETL für DIM_ZEIT - Generierte Dimension
    Erstellt Zeitdimension für Jahre 2020-2027
    """
    print("\n" + "="*60)
    print("ETL: DIM_ZEIT (Generierte Dimension)")
    print("="*60)

    cursor = dwh_conn.cursor()

    # Monatsnamen
    monat_namen = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                   'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember']

    # Wochentagsnamen
    wochentag_namen = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
                       'Freitag', 'Samstag', 'Sonntag']

    start_date = datetime(start_year, 1, 1)
    end_date = datetime(end_year, 12, 31)
    current_date = start_date

    records = []
    while current_date <= end_date:
        # Datum-Key im Format YYYYMMDD
        datum_key = int(current_date.strftime('%Y%m%d'))

        jahr = current_date.year
        monat = current_date.month
        tag = current_date.day

        # Quartal berechnen
        quartal = (monat - 1) // 3 + 1
        quartal_name = f'Q{quartal}'
        jahr_quartal = f'{jahr}-Q{quartal}'

        # Monat
        monat_name = monat_namen[monat - 1]
        jahr_monat = current_date.strftime('%Y-%m')

        # Woche
        woche = int(current_date.strftime('%W'))
        jahr_woche = f'{jahr}-W{woche:02d}'

        # Tag
        tag_im_jahr = current_date.timetuple().tm_yday
        wochentag = current_date.weekday() + 1  # 1=Montag, 7=Sonntag
        wochentag_name = wochentag_namen[current_date.weekday()]

        # Semester (Wintersemester: Okt-März, Sommersemester: Apr-Sep)
        if monat >= 10:
            semester = f'WiSe {jahr}/{(jahr+1)%100:02d}'
        elif monat <= 3:
            semester = f'WiSe {jahr-1}/{jahr%100:02d}'
        else:
            semester = f'SoSe {jahr}'

        # Flags
        ist_wochenende = 1 if wochentag in (6, 7) else 0

        records.append((
            datum_key, current_date.strftime('%Y-%m-%d'),
            jahr,
            quartal, quartal_name, jahr_quartal,
            monat, monat_name, jahr_monat,
            woche, jahr_woche,
            tag, tag_im_jahr, wochentag, wochentag_name,
            semester,
            ist_wochenende, 0  # ist_feiertag default FALSE
        ))

        current_date += timedelta(days=1)

    # Bulk Insert
    cursor.executemany("""
        INSERT INTO DIM_ZEIT (
            datum_key, datum, jahr, quartal, quartal_name, jahr_quartal,
            monat, monat_name, jahr_monat, woche, jahr_woche,
            tag_im_monat, tag_im_jahr, wochentag, wochentag_name,
            semester, ist_wochenende, ist_feiertag
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, records)

    dwh_conn.commit()

    count = len(records)
    print(f"  Eingefügt: {count} Zeitdatensätze ({start_year}-{end_year})")

    # Beispiel anzeigen
    cursor.execute("SELECT * FROM DIM_ZEIT WHERE datum = '2024-01-15' LIMIT 1")
    example = cursor.fetchone()
    print(f"\n  Beispiel: 2024-01-15")
    print(f"    - Datum-Key: {example[0]}")
    print(f"    - Quartal: {example[5]}, Monat: {example[7]}")
    print(f"    - Wochentag: {example[14]}, Semester: {example[15]}")

    log_etl(dwh_conn, 'DIM_ZEIT', count)
    return count

# ============================================================
# ETL: DIM_BUCH (SCD Type 1 - Denormalisierung)
# ============================================================
def etl_dim_buch(oltp_conn, dwh_conn):
    """
    ETL für DIM_BUCH - SCD Type 1
    Denormalisiert Autor, Kategorie, Verlag
    """
    print("\n" + "="*60)
    print("ETL: DIM_BUCH (SCD Type 1 - Denormalisierung)")
    print("="*60)

    oltp_cursor = oltp_conn.cursor()
    dwh_cursor = dwh_conn.cursor()

    # Query mit Denormalisierung
    oltp_cursor.execute("""
        SELECT
            b.buch_id,
            b.isbn,
            b.titel,
            b.erscheinungsjahr,
            b.auflage,

            -- Kategorie denormalisiert
            k.kategorie_id,
            k.kategoriename AS kategorie_name,
            k.beschreibung AS kategorie_beschreibung,

            -- Autor denormalisiert (konkateniert bei mehreren)
            GROUP_CONCAT(a.nachname || ', ' || a.vorname, '; ') AS autor_name,
            MAX(a.nachname) AS hauptautor_nachname,

            -- Verlag denormalisiert
            b.verlag_id,
            v.verlagsname AS verlag_name,
            v.land AS verlag_land,

            -- Exemplar-Anzahl
            COUNT(DISTINCT e.exemplar_id) AS anzahl_exemplare,
            COUNT(DISTINCT CASE WHEN e.status = 'Verfügbar' THEN e.exemplar_id END) AS anzahl_verfuegbar

        FROM BUCH b
        LEFT JOIN KATEGORIE k ON b.kategorie_id = k.kategorie_id
        LEFT JOIN BUCH_AUTOR ba ON b.buch_id = ba.buch_id
        LEFT JOIN AUTOR a ON ba.autor_id = a.autor_id
        LEFT JOIN VERLAG v ON b.verlag_id = v.verlag_id
        LEFT JOIN BUCHEXEMPLAR e ON b.buch_id = e.buch_id
        GROUP BY b.buch_id, b.isbn, b.titel, b.erscheinungsjahr, b.auflage,
                 k.kategorie_id, k.kategoriename, k.beschreibung,
                 b.verlag_id, v.verlagsname, v.land
        ORDER BY b.buch_id
    """)

    books = oltp_cursor.fetchall()

    # Insert in DWH
    inserted = 0
    for book in books:
        dwh_cursor.execute("""
            INSERT INTO DIM_BUCH (
                buch_id, isbn, titel, erscheinungsjahr, auflage,
                kategorie_id, kategorie_name, kategorie_beschreibung,
                autor_name, hauptautor_nachname,
                verlag_id, verlag_name, verlag_land,
                anzahl_exemplare, anzahl_verfuegbar,
                gueltig_von, ist_aktuell
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, DATE('now'), TRUE)
        """, book)
        inserted += 1

    dwh_conn.commit()

    print(f"  Eingefügt: {inserted} Bücher")

    # Statistiken
    dwh_cursor.execute("""
        SELECT kategorie_name, COUNT(*) as anzahl
        FROM DIM_BUCH
        GROUP BY kategorie_name
        ORDER BY anzahl DESC
        LIMIT 5
    """)
    top_kategorien = dwh_cursor.fetchall()

    print(f"\n  Top 5 Kategorien:")
    for kat, anz in top_kategorien:
        print(f"    - {kat}: {anz} Bücher")

    log_etl(dwh_conn, 'DIM_BUCH', inserted)
    return inserted

# ============================================================
# ETL: DIM_MITGLIED (SCD Type 2 - Initial Load)
# ============================================================
def etl_dim_mitglied(oltp_conn, dwh_conn):
    """
    ETL für DIM_MITGLIED - SCD Type 2 (Initial Load)
    Alle als aktuell markiert mit gueltig_von = heute
    """
    print("\n" + "="*60)
    print("ETL: DIM_MITGLIED (SCD Type 2 - Initial Load)")
    print("="*60)

    oltp_cursor = oltp_conn.cursor()
    dwh_cursor = dwh_conn.cursor()

    # Mitglieder aus OLTP laden
    oltp_cursor.execute("""
        SELECT
            p.person_id,
            p.vorname,
            p.nachname,
            p.nachname || ', ' || p.vorname AS name_voll,
            p.email,
            m.mitgliedstyp,
            COALESCE(m.status, 'Aktiv') AS status,
            m.registrierungsdatum
        FROM MITGLIED m
        JOIN PERSON p ON m.person_id = p.person_id
        ORDER BY p.person_id
    """)

    members = oltp_cursor.fetchall()

    # Insert in DWH
    inserted = 0
    for member in members:
        dwh_cursor.execute("""
            INSERT INTO DIM_MITGLIED (
                person_id, vorname, nachname, name_voll, email,
                mitgliedstyp, status, registrierungsdatum,
                gueltig_von, gueltig_bis, ist_aktuell
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE('now'), NULL, TRUE)
        """, member)
        inserted += 1

    dwh_conn.commit()

    print(f"  Eingefügt: {inserted} Mitglieder")

    # Statistiken nach Typ
    dwh_cursor.execute("""
        SELECT mitgliedstyp, COUNT(*) as anzahl
        FROM DIM_MITGLIED
        WHERE ist_aktuell = TRUE
        GROUP BY mitgliedstyp
        ORDER BY anzahl DESC
    """)
    types = dwh_cursor.fetchall()

    print(f"\n  Verteilung nach Typ:")
    for typ, anz in types:
        print(f"    - {typ}: {anz} Mitglieder")

    log_etl(dwh_conn, 'DIM_MITGLIED', inserted)
    return inserted


# ============================================================
# ETL: FACT_AUSLEIHE (Transaction Fact)
# ============================================================
def etl_fact_ausleihe(oltp_conn, dwh_conn):
    """
    ETL für FACT_AUSLEIHE - Transaction Fact Table
    """
    print("\n" + "="*60)
    print("ETL: FACT_AUSLEIHE (Transaction Fact)")
    print("="*60)

    oltp_cursor = oltp_conn.cursor()
    dwh_cursor = dwh_conn.cursor()

    # Ausleihen aus OLTP laden
    oltp_cursor.execute("""
        SELECT
            a.ausleihe_id,
            a.ausleihdatum,
            a.fälligkeitsdatum,
            a.rückgabedatum,
            e.buch_id,
            a.mitglied_person_id,
            a.bibliothekar_person_id,

            -- Berechnungen
            CASE
                WHEN a.rückgabedatum IS NOT NULL
                THEN CAST((JULIANDAY(a.rückgabedatum) - JULIANDAY(a.ausleihdatum)) AS INTEGER)
                ELSE NULL
            END AS ausleihdauer_tage,

            CAST((JULIANDAY(a.fälligkeitsdatum) - JULIANDAY(a.ausleihdatum)) AS INTEGER) AS ausleihdauer_soll_tage,

            CASE
                WHEN a.rückgabedatum IS NULL AND DATE('now') > a.fälligkeitsdatum
                THEN CAST((JULIANDAY(DATE('now')) - JULIANDAY(a.fälligkeitsdatum)) AS INTEGER)
                WHEN a.rückgabedatum IS NOT NULL AND a.rückgabedatum > a.fälligkeitsdatum
                THEN CAST((JULIANDAY(a.rückgabedatum) - JULIANDAY(a.fälligkeitsdatum)) AS INTEGER)
                ELSE 0
            END AS tage_ueberfaellig,

            CASE
                WHEN a.rückgabedatum IS NOT NULL THEN 1
                ELSE 0
            END AS ist_zurueckgegeben,

            CASE
                WHEN a.rückgabedatum IS NULL AND DATE('now') > a.fälligkeitsdatum THEN 1
                WHEN a.rückgabedatum IS NOT NULL AND a.rückgabedatum > a.fälligkeitsdatum THEN 0
                ELSE 0
            END AS ist_ueberfaellig,

            CASE
                WHEN a.rückgabedatum IS NOT NULL AND a.rückgabedatum > a.fälligkeitsdatum THEN 1
                ELSE 0
            END AS ist_verspaetet,

            COALESCE(a.status,
                CASE
                    WHEN a.rückgabedatum IS NOT NULL THEN 'Zurückgegeben'
                    WHEN DATE('now') > a.fälligkeitsdatum THEN 'Überfällig'
                    ELSE 'Ausgeliehen'
                END
            ) AS status

        FROM AUSLEIHE a
        JOIN BUCHEXEMPLAR e ON a.exemplar_id = e.exemplar_id
        ORDER BY a.ausleihdatum
    """)

    loans = oltp_cursor.fetchall()

    # Insert in DWH
    inserted = 0
    skipped = 0

    for loan in loans:
        (ausleih_id, ausleihdatum, soll_rueckgabedatum, rueckgabedatum,
         buch_id, person_id, bibliothekar_id,
         ausleihdauer_tage, ausleihdauer_soll_tage, tage_ueberfaellig,
         ist_zurueckgegeben, ist_ueberfaellig, ist_verspaetet, status) = loan

        # Datum-Keys erstellen
        datum_ausleihe_key = int(ausleihdatum.replace('-', ''))
        datum_faelligkeit_key = int(soll_rueckgabedatum.replace('-', ''))
        datum_rueckgabe_key = int(rueckgabedatum.replace('-', '')) if rueckgabedatum else None

        # Lookup: buch_key aus DIM_BUCH
        dwh_cursor.execute("SELECT buch_key FROM DIM_BUCH WHERE buch_id = ? AND ist_aktuell = TRUE", (buch_id,))
        buch = dwh_cursor.fetchone()
        if not buch:
            skipped += 1
            continue
        buch_key = buch[0]

        # Lookup: mitglied_key aus DIM_MITGLIED
        dwh_cursor.execute("SELECT mitglied_key FROM DIM_MITGLIED WHERE person_id = ? AND ist_aktuell = TRUE", (person_id,))
        mitglied = dwh_cursor.fetchone()
        if not mitglied:
            skipped += 1
            continue
        mitglied_key = mitglied[0]

        # Strafbetrag berechnen (0.50 EUR pro Tag)
        strafbetrag = tage_ueberfaellig * 0.50 if tage_ueberfaellig > 0 else 0.00

        # Insert
        dwh_cursor.execute("""
            INSERT INTO FACT_AUSLEIHE (
                datum_ausleihe_key, datum_faelligkeit_key, datum_rueckgabe_key,
                buch_key, mitglied_key,
                ausleihe_id, bibliothekar_person_id,
                ausleihdauer_tage, ausleihdauer_soll_tage, strafbetrag, tage_ueberfaellig,
                ist_zurueckgegeben, ist_ueberfaellig, ist_verspaetet, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (datum_ausleihe_key, datum_faelligkeit_key, datum_rueckgabe_key,
              buch_key, mitglied_key, ausleih_id, bibliothekar_id,
              ausleihdauer_tage, ausleihdauer_soll_tage, strafbetrag, tage_ueberfaellig,
              ist_zurueckgegeben, ist_ueberfaellig, ist_verspaetet, status))
        inserted += 1

    dwh_conn.commit()

    print(f"  Eingefügt: {inserted} Ausleihen")
    if skipped > 0:
        print(f"  Übersprungen: {skipped} (fehlende Dimension-Referenzen)")

    # Statistiken
    dwh_cursor.execute("""
        SELECT
            COUNT(*) as gesamt,
            SUM(CASE WHEN ist_zurueckgegeben THEN 1 ELSE 0 END) as zurueckgegeben,
            SUM(CASE WHEN ist_ueberfaellig THEN 1 ELSE 0 END) as ueberfaellig,
            SUM(CASE WHEN ist_verspaetet THEN 1 ELSE 0 END) as verspaetet,
            ROUND(AVG(ausleihdauer_tage), 2) as avg_dauer,
            ROUND(SUM(strafbetrag), 2) as gesamt_strafen
        FROM FACT_AUSLEIHE
    """)
    stats = dwh_cursor.fetchone()

    print(f"\n  Statistiken:")
    print(f"    - Gesamt: {stats[0]}")
    print(f"    - Zurückgegeben: {stats[1]}")
    print(f"    - Überfällig: {stats[2]}")
    print(f"    - Verspätet: {stats[3]}")
    print(f"    - Ø Ausleihdauer: {stats[4]} Tage")
    print(f"    - Gesamt Strafen: {stats[5]} EUR")

    log_etl(dwh_conn, 'FACT_AUSLEIHE', inserted)
    return inserted

# ============================================================
# ETL: FACT_RESERVIERUNG (Accumulating Snapshot)
# ============================================================
def etl_fact_reservierung(oltp_conn, dwh_conn):
    """
    ETL für FACT_RESERVIERUNG - Accumulating Snapshot Fact
    """
    print("\n" + "="*60)
    print("ETL: FACT_RESERVIERUNG (Accumulating Snapshot)")
    print("="*60)

    oltp_cursor = oltp_conn.cursor()
    dwh_cursor = dwh_conn.cursor()

    # Reservierungen aus OLTP laden
    oltp_cursor.execute("""
        SELECT
            r.reservierung_id,
            r.reservierungsdatum,
            NULL AS abholungsdatum,  -- OLTP hat kein abholungsdatum
            r.buch_id,
            r.mitglied_person_id,
            r.status,

            -- Wartezeit berechnen (NULL wenn nicht abgeholt)
            NULL AS wartezeit_tage

        FROM RESERVIERUNG r
        ORDER BY r.reservierungsdatum
    """)

    reservations = oltp_cursor.fetchall()

    # Insert in DWH
    inserted = 0
    skipped = 0

    for res in reservations:
        (reservierung_id, reservierungsdatum, abholungsdatum,
         buch_id, person_id, status_text, wartezeit_tage) = res

        # Datum-Keys
        datum_reservierung_key = int(reservierungsdatum.replace('-', ''))
        datum_erfuellung_key = int(abholungsdatum.replace('-', '')) if abholungsdatum else None

        # Lookup: buch_key
        dwh_cursor.execute("SELECT buch_key FROM DIM_BUCH WHERE buch_id = ? AND ist_aktuell = TRUE", (buch_id,))
        buch = dwh_cursor.fetchone()
        if not buch:
            skipped += 1
            continue
        buch_key = buch[0]

        # Lookup: mitglied_key
        dwh_cursor.execute("SELECT mitglied_key FROM DIM_MITGLIED WHERE person_id = ? AND ist_aktuell = TRUE", (person_id,))
        mitglied = dwh_cursor.fetchone()
        if not mitglied:
            skipped += 1
            continue
        mitglied_key = mitglied[0]

        # Status-Flags
        ist_aktiv = 1 if status_text == 'aktiv' else 0
        ist_erfuellt = 1 if status_text == 'abgeholt' else 0
        ist_storniert = 1 if status_text == 'storniert' else 0
        ist_abgelaufen = 1 if status_text == 'abgelaufen' else 0

        # Insert
        dwh_cursor.execute("""
            INSERT INTO FACT_RESERVIERUNG (
                datum_reservierung_key, datum_erfuellung_key,
                buch_key, mitglied_key,
                reservierung_id, wartezeit_tage,
                ist_aktiv, ist_erfuellt, ist_storniert, ist_abgelaufen, status
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (datum_reservierung_key, datum_erfuellung_key, buch_key, mitglied_key,
              reservierung_id, wartezeit_tage,
              ist_aktiv, ist_erfuellt, ist_storniert, ist_abgelaufen, status_text))
        inserted += 1

    dwh_conn.commit()

    print(f"  Eingefügt: {inserted} Reservierungen")
    if skipped > 0:
        print(f"  Übersprungen: {skipped} (fehlende Dimension-Referenzen)")

    # Statistiken
    dwh_cursor.execute("""
        SELECT
            COUNT(*) as gesamt,
            SUM(ist_aktiv) as aktiv,
            SUM(ist_erfuellt) as erfuellt,
            SUM(ist_storniert) as storniert,
            SUM(ist_abgelaufen) as abgelaufen,
            ROUND(AVG(wartezeit_tage), 2) as avg_wartezeit
        FROM FACT_RESERVIERUNG
    """)
    stats = dwh_cursor.fetchone()

    print(f"\n  Statistiken:")
    print(f"    - Gesamt: {stats[0]}")
    print(f"    - Aktiv: {stats[1]}")
    print(f"    - Erfüllt: {stats[2]}")
    print(f"    - Storniert: {stats[3]}")
    print(f"    - Abgelaufen: {stats[4]}")
    print(f"    - Ø Wartezeit: {stats[5]} Tage")

    log_etl(dwh_conn, 'FACT_RESERVIERUNG', inserted)
    return inserted

def main():
    """Hauptprogramm: Führt kompletten ETL-Prozess durch"""
    # == == == == == == == == == == == == == == == == == == == == == == == == == == == == == ==
    # DATA WAREHOUSE ETL - PROZESS
    # Bibliotheksverwaltungssystem
    # == == == == == == == == == == == == == == == == == == == == == == == == == == == == == ==
    print("\n" + "="*60)
    print("DATA WAREHOUSE ETL-PROZESS")
    print("Bibliotheksverwaltungssystem")
    print("="*60)
    print(f"Start: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Verbindungen öffnen
    print(f"\nVerbinde zu OLTP: {OLTP_DB}")
    print(f"Verbinde zu DWH:  {DWH_DB}")

    try:
        oltp_conn = sqlite3.connect(OLTP_DB)
        dwh_conn = sqlite3.connect(DWH_DB)

        # Tabellen vor ETL leeren
        truncate_tables(dwh_conn)

        # ETL-Prozesse ausführen
        total_zeit = etl_dim_zeit(dwh_conn)
        total_buch = etl_dim_buch(oltp_conn, dwh_conn)
        total_mitglied = etl_dim_mitglied(oltp_conn, dwh_conn)
        total_ausleihe = etl_fact_ausleihe(oltp_conn, dwh_conn)
        total_reservierung = etl_fact_reservierung(oltp_conn, dwh_conn)

        # == == == == == == == == == == == == == == == == == == == == == == == == == == == == == ==
        # ETL - PROZESS ERFOLGREICH ABGESCHLOSSEN
        # == == == == == == == == == == == == == == == == == == == == == == == == == == == == == ==
        # Abschluss
        print("\n" + "="*60)
        print("ETL-PROZESS ERFOLGREICH ABGESCHLOSSEN")
        print("="*60)
        print(f"\nZusammenfassung:")
        print(f"  - DIM_ZEIT:          {total_zeit:,} Datensätze")
        print(f"  - DIM_BUCH:          {total_buch:,} Datensätze")
        print(f"  - DIM_MITGLIED:      {total_mitglied:,} Datensätze")
        print(f"  - FACT_AUSLEIHE:     {total_ausleihe:,} Datensätze")
        print(f"  - FACT_RESERVIERUNG: {total_reservierung:,} Datensätze")
        print(f"\nGesamt: {total_zeit + total_buch + total_mitglied + total_ausleihe + total_reservierung:,} Datensätze geladen")
        print(f"\nEnde: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("="*60)

    except Exception as e:
        print(f"\nFEHLER: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        oltp_conn.close()
        dwh_conn.close()

    return 0

if __name__ == '__main__':
    sys.exit(main())
