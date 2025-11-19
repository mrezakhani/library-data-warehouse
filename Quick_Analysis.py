import sqlite3

conn = sqlite3.connect('bibliothek_dwh.db')
cursor = conn.cursor()

print("\n" + "="*80)
print("ANALYTISCHE AUSWERTUNGEN - DATA WAREHOUSE BIBLIOTHEKSVERWALTUNG")
print("="*80)

print("\n" + "="*80)
print("ANALYSE 1: Ausleihtrends nach Kategorie (Frage 1)")
print("="*80)

print("\n>>> Top 5 Kategorien nach Gesamtausleihen:")
cursor.execute("""
    SELECT
        b.kategorie_name,
        COUNT(f.ausleihe_key) AS ausleihen,
        ROUND(AVG(CASE WHEN f.ist_zurueckgegeben THEN f.ausleihdauer_tage END), 1) AS avg_dauer,
        SUM(f.ist_ueberfaellig) AS ueberfaellig,
        ROUND(100.0 * SUM(f.ist_ueberfaellig) / COUNT(*), 1) AS rate,
        ROUND(SUM(f.strafbetrag), 2) AS strafen
    FROM FACT_AUSLEIHE f
    JOIN DIM_BUCH b ON f.buch_key = b.buch_key
    GROUP BY b.kategorie_name
    ORDER BY ausleihen DESC
    LIMIT 5
""")
for row in cursor.fetchall():
    dauer = f"{row[2]:4.1f}" if row[2] else "N/A"
    print(f"  {row[0]:20} | {row[1]:3} Ausl. | Dauer: {dauer} T | Uberf: {row[3]:2} ({row[4]:4.1f}%) | {row[5]:7.2f} EUR")

print("\n>>> Ausleihentwicklung nach Jahr:")
cursor.execute("""
    SELECT
        z.jahr,
        COUNT(f.ausleihe_key) AS ausleihen,
        ROUND(AVG(CASE WHEN f.ist_zurueckgegeben THEN f.ausleihdauer_tage END), 1) AS avg_dauer,
        SUM(f.ist_ueberfaellig) AS ueberfaellig,
        ROUND(SUM(f.strafbetrag), 2) AS strafen
    FROM FACT_AUSLEIHE f
    JOIN DIM_ZEIT z ON f.datum_ausleihe_key = z.datum_key
    GROUP BY z.jahr
    ORDER BY z.jahr
""")
for row in cursor.fetchall():
    dauer = f"{row[2]:5.1f}" if row[2] else " N/A"
    print(f"  {row[0]} | {row[1]:3} Ausleihen | Dauer: {dauer} T | Uberf: {row[3]:2} | Strafen: {row[4]:6.2f} EUR")

print("\n>>> Ausleihtrends nach Semester:")
cursor.execute("""
    SELECT
        z.semester,
        COUNT(f.ausleihe_key) AS ausleihen,
        COUNT(DISTINCT b.kategorie_name) AS kategorien,
        SUM(f.ist_ueberfaellig) AS ueberfaellig
    FROM FACT_AUSLEIHE f
    JOIN DIM_ZEIT z ON f.datum_ausleihe_key = z.datum_key
    JOIN DIM_BUCH b ON f.buch_key = b.buch_key
    GROUP BY z.semester
    ORDER BY z.semester DESC
    LIMIT 6
""")
for row in cursor.fetchall():
    print(f"  {row[0]:15} | {row[1]:3} Ausleihen | {row[2]} Kategorien | Uberf: {row[3]:2}")

print("\n" + "="*80)
print("ANALYSE 2: Bedarfsanalyse fur Buchanschaffungen (Frage 5)")
print("="*80)

print("\n>>> Top 10 Bucher mit hochstem Anschaffungsbedarf:")
cursor.execute("""
    SELECT
        b.titel,
        b.kategorie_name,
        b.anzahl_exemplare,
        COUNT(DISTINCT f.ausleihe_key) AS ausleihen,
        COUNT(DISTINCT r.reservierung_key) AS reservierungen
    FROM DIM_BUCH b
    LEFT JOIN FACT_AUSLEIHE f ON b.buch_key = f.buch_key
    LEFT JOIN FACT_RESERVIERUNG r ON b.buch_key = r.buch_key
    WHERE b.ist_aktuell = TRUE
    GROUP BY b.buch_key, b.titel, b.kategorie_name, b.anzahl_exemplare
    HAVING ausleihen > 0 OR reservierungen > 0
    ORDER BY (reservierungen * 10.0 / NULLIF(b.anzahl_exemplare, 1) +
              ausleihen * 5.0 / NULLIF(b.anzahl_exemplare, 1)) DESC
    LIMIT 10
""")
print(f"  Nr | {'Titel':<42} | Kat  | Ex | Ausl | Res")
print(f"  {'-'*75}")
for i, row in enumerate(cursor.fetchall(), 1):
    titel = (row[0][:39] + '...') if len(row[0]) > 42 else row[0]
    kat = row[1][:4]
    print(f"  {i:2} | {titel:<42} | {kat} | {row[2]:2} | {row[3]:4} | {row[4]:3}")

print("\n>>> Anschaffungsempfehlungen nach Kategorie:")
cursor.execute("""
    SELECT
        b.kategorie_name,
        COUNT(DISTINCT b.buch_key) AS bucher,
        SUM(b.anzahl_exemplare) AS exemplare,
        COUNT(DISTINCT f.ausleihe_key) AS ausleihen,
        COUNT(DISTINCT r.reservierung_key) AS reservierungen,
        ROUND(CAST(COUNT(DISTINCT f.ausleihe_key) AS FLOAT) / NULLIF(SUM(b.anzahl_exemplare), 0), 1) AS ausl_pro_ex
    FROM DIM_BUCH b
    LEFT JOIN FACT_AUSLEIHE f ON b.buch_key = f.buch_key
    LEFT JOIN FACT_RESERVIERUNG r ON b.buch_key = r.buch_key
    WHERE b.ist_aktuell = TRUE
    GROUP BY b.kategorie_name
    ORDER BY ausl_pro_ex DESC
""")
for row in cursor.fetchall():
    ausl_ex = f"{row[5]:4.1f}" if row[5] else "0.0"
    print(f"  {row[0]:20} | {row[1]:2} Bucher | {row[2]:3} Ex | {row[3]:3} Ausl | {row[4]:2} Res | {ausl_ex} Ausl/Ex")

print("\n" + "="*80)
print("ANALYSE 3: Mitglieder-Segmentierung")
print("="*80)

print("\n>>> Ausleihverhalten nach Mitgliedstyp:")
cursor.execute("""
    SELECT
        m.mitgliedstyp,
        COUNT(DISTINCT m.mitglied_key) AS mitglieder,
        COUNT(f.ausleihe_key) AS ausleihen,
        ROUND(CAST(COUNT(f.ausleihe_key) AS FLOAT) / NULLIF(COUNT(DISTINCT m.mitglied_key), 0), 1) AS ausl_pro_mitgl,
        SUM(f.ist_ueberfaellig) AS ueberfaellig,
        ROUND(SUM(f.strafbetrag), 2) AS strafen
    FROM DIM_MITGLIED m
    LEFT JOIN FACT_AUSLEIHE f ON m.mitglied_key = f.mitglied_key
    WHERE m.ist_aktuell = TRUE
    GROUP BY m.mitgliedstyp
    ORDER BY ausl_pro_mitgl DESC
""")
for row in cursor.fetchall():
    ausl_mitgl = f"{row[3]:5.1f}" if row[3] else "  0.0"
    ueberfaellig = row[4] if row[4] is not None else 0
    strafen = row[5] if row[5] is not None else 0.0
    print(f"  {row[0]:12} | {row[1]:2} Mitgl | {row[2]:3} Ausl | {ausl_mitgl} Ausl/Mitgl | Uberf: {ueberfaellig:2} | {strafen:7.2f} EUR")

print("\n>>> Top 10 aktivste Mitglieder:")
cursor.execute("""
    SELECT
        m.name_voll,
        m.mitgliedstyp,
        COUNT(f.ausleihe_key) AS ausleihen,
        SUM(f.ist_ueberfaellig) AS ueberfaellig,
        ROUND(SUM(f.strafbetrag), 2) AS strafen
    FROM DIM_MITGLIED m
    JOIN FACT_AUSLEIHE f ON m.mitglied_key = f.mitglied_key
    WHERE m.ist_aktuell = TRUE
    GROUP BY m.mitglied_key, m.name_voll, m.mitgliedstyp
    ORDER BY ausleihen DESC
    LIMIT 10
""")
for i, row in enumerate(cursor.fetchall(), 1):
    ueberfaellig = row[3] if row[3] is not None else 0
    strafen = row[4] if row[4] is not None else 0.0
    print(f"  {i:2}. {row[0]:28} | {row[1]:10} | {row[2]:2} Ausl | Uberf: {ueberfaellig} | {strafen:6.2f} EUR")

print("\n" + "="*80)
print("KEY PERFORMANCE INDICATORS (KPIs)")
print("="*80)

cursor.execute("""
    SELECT
        (SELECT COUNT(*) FROM DIM_BUCH WHERE ist_aktuell = TRUE),
        (SELECT COUNT(*) FROM DIM_MITGLIED WHERE ist_aktuell = TRUE),
        (SELECT COUNT(*) FROM FACT_AUSLEIHE),
        (SELECT COUNT(*) FROM FACT_AUSLEIHE WHERE ist_zurueckgegeben = FALSE),
        (SELECT COUNT(*) FROM FACT_AUSLEIHE WHERE ist_ueberfaellig = TRUE),
        (SELECT ROUND(AVG(ausleihdauer_tage), 1) FROM FACT_AUSLEIHE WHERE ist_zurueckgegeben = TRUE),
        (SELECT ROUND(SUM(strafbetrag), 2) FROM FACT_AUSLEIHE),
        (SELECT COUNT(*) FROM FACT_RESERVIERUNG)
""")
kpis = cursor.fetchone()

print(f"""
  Bibliotheksbestand:          {kpis[0]:>5} Bucher
  Aktive Mitglieder:           {kpis[1]:>5} Personen

  Ausleihen gesamt:            {kpis[2]:>5}
  Aktuell ausgeliehen:         {kpis[3]:>5} Bucher
  Uberfaellig:                 {kpis[4]:>5} Bucher ({100*kpis[4]/kpis[2]:.1f}%)

  Durchschn. Ausleihdauer:     {kpis[5]:>5.1f} Tage
  Gesamt Strafgebuehren:       {kpis[6]:>8.2f} EUR

  Reservierungen gesamt:       {kpis[7]:>5}
""")

print("="*80)
print("ANALYSE ABGESCHLOSSEN")
print("="*80 + "\n")

conn.close()
