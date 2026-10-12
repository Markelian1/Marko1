# Lidhja e Raportit me cTrader

Sapo mbyllet një trade në cTrader, ai shkruhet vetë si rresht i ri te **Raporti i Analizave** në Google Sheets.

```
cTrader (cBot RaportiSync)  ──►  Google Apps Script (Web app)  ──►  fleta "Raporti"
```

Duhen 3 hapa, që bëhen vetëm një herë.

---

## Hapi 1 – Raporti në Google Sheets

Raporti duhet të jetë **Google Sheets i vërtetë**, jo skedar `.xlsx`, ndryshe nuk shfaqet menyja Apps Script.
Bëje nga kompjuteri (në shfletues), sepse në aplikacionin e telefonit nuk ka Apps Script.

1. Hap **sheets.new** në shfletues (krijon një fletë të re bosh).
2. **File → Import → Upload** → zgjidh `Raporti_i_Analizave.xlsx`.
3. Te *Import location* zgjidh **Replace spreadsheet** → **Import data**.
4. Riemërtoje lart majtas (p.sh. *Raporti i Analizave*).
5. Fshi rreshtin shembull: zgjidh qelizat **B12:I12** dhe shtyp **Delete** (mos e fshi gjithë rreshtin).

Si e kupton që është në rregull: pranë emrit lart **nuk** duhet të shkruajë `.XLSX`, dhe te menyja **Extensions** shfaqet **Apps Script**.

## Hapi 2 – Google Apps Script

1. Te raporti: **Extensions → Apps Script**.
2. Fshi kodin që gjen aty dhe ngjit gjithë përmbajtjen e `GoogleAppsScript.gs`.
3. Te rreshti `const TOKEN = 'NDRYSHO-KETE';` vendos një fjalëkalim tëndin (p.sh. `marko-2026-x7`). **Ruaje** (ikona e diskut).
4. **Deploy → New deployment** → te ⚙️ zgjidh **Web app**:
   - *Execute as*: **Me**
   - *Who has access*: **Anyone**
5. **Deploy** → **Authorize access** → zgjidh llogarinë → *Advanced* → *Go to … (unsafe)* → **Allow**.
   (Paralajmërimi del sepse skripti është yti dhe nuk është verifikuar nga Google.)
6. Kopjo **Web app URL** (mbaron me `/exec`).
7. Provë: hape URL-në në shfletues, duhet të shkruajë *"Lidhja me Raportin e Analizave punon."*
8. **Grafikët:** lart në Apps Script, te lista e funksioneve (pranë ▷ Run), zgjidh **rregulloRaportin** dhe kliko **▷ Run**.
   Ndërton grafikët Balance dhe Winrate direkt në Google Sheets dhe rikthen formulat nëse janë fshirë.

> Nëse e ndryshon kodin më vonë: **Deploy → Manage deployments → ✏️ → Version: New version → Deploy**.
> Përndryshe URL-ja vazhdon të përdorë kodin e vjetër.

## Hapi 3 – cBot-i në cTrader

1. Në cTrader hap **Algo** → **cBots** → **New** (emri: `RaportiSync`).
2. Fshi kodin që gjen aty dhe ngjit gjithë përmbajtjen e `RaportiSync.cs`. Pastaj **Build** (Ctrl+B).
3. **Add instance** (çdo simbol dhe timeframe shkon) dhe plotëso parametrat:

| Parametri | Çfarë vendos |
|---|---|
| URL e Google Script | URL-ja `/exec` nga Hapi 2 |
| Token (fjalëkalimi) | i njëjti fjalëkalim si `TOKEN` te skripti |
| Importo historinë (ditë) | `0` = vetëm trade-t e reja. P.sh. `300` herën e parë për të futur edhe trade-t e vjetra, pastaj ktheje në `0` |
| Kufiri BE (R) | `0.2`: mbyllja brenda ±0.2R nga hyrja quhet BE |
| Kufiri BE pa SL (pips) | `3`: për trade pa SL, ±3 pips quhet BE |

4. **Start**. Te skeda **Log** duhet të shkruajë *"RaportiSync u nis…"* dhe pas çdo mbyllje *"Pozicioni #… u shkrua te Raporti."*

cBot-i duhet të jetë **ndezur** (cTrader i hapur në PC ose VPS). Nëse e fik, kur e ndez prapë dërgon trade-t që u mbyllën ndërkohë.
Mos e nis në cTrader Cloud, sepse atje lidhja me internetin mund të jetë e bllokuar.

---

## Si plotësohen kolonat

| Kolona | Nga vjen |
|---|---|
| Data | data e hapjes së pozicionit |
| Pair | simboli (`EURJPY` → `EUR/JPY`, `US30` mbetet `US30`) |
| Setup | *Comment* (ose *Label*) e pozicionit. Nëse është bosh, shkruaje vetë |
| R:R | largësia e TP / largësia e SL, sipas SL dhe TP **fillestare** (edhe nëse SL-në e çove më vonë në BE). Del vetëm nëse cBot-i ishte ndezur kur u hap trade-i, përndryshe mbetet bosh dhe e shkruan vetë |
| Status i pozitës | shih më poshtë |
| Shënime | fitimi/humbja reale, % e llogarisë, pips dhe ID e pozicionit në cTrader |

**Statusi** caktohet nga çmimi i mbylljes së fundit, krahasuar me hyrjen dhe SL-në fillestare:

- mbi +0.2R → **TP**
- brenda ±0.2R → **BE**
- nën −0.2R → **LOSS**
- nëse pozicioni u mbyll në më shumë se një pjesë (partial close) dhe pjesa e fundit doli TP ose BE → **CLOSE HALF - TP** / **CLOSE HALF - BE**

Kujdes: një trade i mbyllur me dorë në fitim (p.sh. +0.5R) del **TP**. Nëse s'është e saktë, ndryshoje statusin me dorë te raporti.

## Nëse diçka nuk punon

Kur Google nuk e pranon një trade, cBot-i shkruan te **Logs** `GABIM: … NUK u shkrua. Google: …` dhe ndalon.
Rregulloje sipas tabelës, pastaj nise prapë: trade-t e padërguara dërgohen atëherë.

| Mesazhi te Logs | Zgjidhja |
|---|---|
| `token i gabuar` | `TOKEN` te skripti duhet të jetë **saktësisht** si Token te cBot-i. Pastaj: Save → Deploy → Manage deployments → ✏️ → New version |
| `kodi 401`, `kodi 403`, `Moved Temporarily` ose `Sign in` | Web app-i kërkon hyrje në Google. Bëj **Deploy → New deployment → Web app** me *Who has access: **Anyone*** dhe vendos URL-në e re `/exec` te cBot-i. Provë: hape URL-në në dritare Incognito, duhet të dalë *"Lidhja … punon"* pa kërkuar hyrje |
| `Script function not found: doPost` | Kodi nuk u ruajt para Deploy. Save → Manage deployments → ✏️ → New version |
| `skripti nuk është i lidhur me raportin` | Krijoje skriptin nga vetë raporti: Extensions → Apps Script |
| `Dërgimi dështoi (kodi 404)` | URL-ja është e gabuar. Kopjo prapë Web app URL (`/exec`) |
| `raporti është plot` | Janë mbushur 500 rreshta. Fillo një raport të ri për vitin tjetër |
| Nuk shfaqet asgjë te raporti | Kontrollo që fleta të quhet saktë `Raporti` dhe që e ke ruajtur si Google Sheets (Hapi 1) |
