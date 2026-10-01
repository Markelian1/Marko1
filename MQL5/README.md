# CRT MTF EA (MT5)

Expert Advisor për MetaTrader 5, i ndërtuar nga indikatorët TradingView
"CRT MTF EVENT ENGINE v8 - 5M FINAL - NO 1M" dhe "v5 + v6 1M MICRO ENGINE".
Vlerat fillestare janë zgjedhur për **XAUUSD**.

Skedari: `Experts/CRT_MTF_EA.mq5` (v1.26)

## Pse v1.10 humbi rreth 48% në 5 javë (XAUUSD M5, 2023)

Nga journal-i i testit:

- Stop-et ishin shumë të vogla: $0.32–$1.09. Spread-i ishte $0.18–$0.26,
  pra **20–50% e rrezikut të çdo trade-i shkonte te spread-i**.
- Me rrezik 0.5% dhe stop kaq të ngushtë, lotet dilnin 2.8–5.
- Shumë "sweep" ishin vetëm disa cent mbi/nën parent range, pra zhurmë
  dhe jo marrje likuiditeti.
- Pa limit ditor (14+ trade në ditë) dhe me trade edhe në 22:00–23:30
  (rollover, spread i gjerë), kostoja shumëfishohej.

Me këto kosto, një stop dhe target kaq afër janë matematikisht humbës,
pavarësisht nga ideja e CRT-së.

## Si funksionon

1. Shtatë motorë CRT (1W, 1D, 4H, 1H, 30M, 15M, 5M) punojnë vetëm me qirinj
   të mbyllur: parent → sweep → mbyllje brenda range-it → CRT.
2. **v8, modaliteti fillestar (`ENTRY_CRT_CLOSE`)**: kur mbyllet CRT-ja 5M,
   hapet trade me çmim tregu.
   - **SL** përtej wick-ut të qiririt që bëri sweep-in (C2) + buffer
   - **TP** te target-i i CRT-së 5M (ana tjetër e parent range), ose R fiks
   - Nëse CRT-ja 5M invalidohet (mbyllje jashtë parent range) ndërsa trade-i
     është hapur, trade-i mbyllet (`InpCloseOnInvalid`).
3. **Modaliteti opsional `ENTRY_MICRO_1M`**: pas CRT-së 5M, EA-ja pret në 1M
   sweep → MSS → FVG → retest dhe hyn te retest-i, me SL përtej sweep-it 1M.
   Shërben për të krahasuar nëse filtri 1M sjell ndonjë përfitim.

## Çfarë u rregullua nga versioni Pine

| Problemi në Pine | Në EA |
|---|---|
| Rregulli 50% ishte i kthyer mbrapsht (bull: `low <= 50%`) | Si parazgjedhje entry mbyllet kur çmimi ka bërë 50% të rrugës **drejt target-it**. Rregulli v5 mbetet si opsion. |
| Eventet zbuloheshin me `!=` kundrejt `na` | Eventet vijnë direkt nga motori |
| 5M vinte me një bar vonesë (`[1]` në chart 5M) | Motori 5M punon me qirinj M5 të mbyllur, pa vonesë shtesë |
| Historia 1M fshihej te çdo CRT e re | Historia 1M është e vazhdueshme, ndaj sweep-i mund të ndodhë te qiriri i parë |
| `MSS Lookback` nuk përdorej | Sweep-i dhe MSS kanë lookback të veçantë |
| Motori 1M mund të hynte pasi ishte prekur target-i | Target-i dhe 50% kontrollohen në çdo qiri 1M |
| Qiriri 1M që po formohej shkaktonte repaint | Përdoren vetëm qirinj 1M të mbyllur |
| Ledger-i ruante TARGET/INVALID me nivelet e reja | Ledger-i ruan nivelet e CRT-së që sapo u mbyll |

## Instalimi

1. Kopjo `Experts/CRT_MTF_EA.mq5` te `MQL5/Experts/` e terminalit
   (MT5: File → Open Data Folder).
2. Hape në MetaEditor dhe shtyp **F7** për ta kompiluar.
3. Tërhiqe EA-në mbi grafikun XAUUSD. Timeframe-i i grafikut nuk ka rëndësi;
   M5 është më i miri për ta ndjekur vizualisht.

> Kodi **nuk është kompiluar** në mjedisin ku u shkrua, sepse aty nuk ka
> MetaEditor. Nëse F7 jep gabime, dërgoji dhe rregullohen.

## Testimi në Strategy Tester

- Symbol: XAUUSD (ose emri që përdor brokeri, p.sh. `XAUUSD.m`, `GOLD`)
- Modeli: **Every tick based on real ticks**, ose të paktën **1 minute OHLC**.
  Mos përdor "Open prices only", sepse EA-ja punon me qirinj 1M.
- Visual mode: shfaq nivelet 5M, eventet 1M dhe panelin.
- Për krahasim, testo si `ENTRY_CRT_CLOSE` (v8) ashtu edhe `ENTRY_MICRO_1M`.

## Parametrat (v1.26, vlerat fillestare)

Vlerat fillestare janë konfigurimi i zgjedhur nga optimizimet 2023–2026.
Kur e vendos EA-në në grafik (ose shtyp **Reset** te Inputs), nuk ke nevojë të ndryshosh asgjë.

| Grupi | Parametri | Vlera | Çfarë bën |
|---|---|---|---|
| 1. STRATEGY | Entry mode | CRT close | hyn kur konfirmohet CRT-ja |
| | CRT entry timeframe | **15 Minutes** | CRT-ja që jep hyrjen |
| | HTF bias filter | **Require an active HTF CRT in the same direction** | hyn vetëm në drejtimin e CRT-së së HTF-së |
| | HTF bias timeframe | **1 Day** | CRT-ja ditore jep drejtimin |
| 2. RISK | Risk per trade | 0.5% | humbja nëse preket SL-ja |
| | Max lots | 5.0 | kufi sigurie |
| | Max trades per day | 3 | |
| 3. STOP / TARGET | Stop loss placement | CRT sweep wick (C2) | SL përtej wick-ut + 0.30 $ |
| | Take profit | CRT target | ana tjetër e parent range |
| | Min reward:risk | 1.0 | trade-t me RR < 1 anashkalohen |
| | Move SL to entry at +R | 0 (fikur) | break-even-i doli më keq në optimizim |
| | Close when CRT invalidated | true | del kur CRT-ja prishet |
| 4. FILTERS | Min SL | 1.00 $ | stop-et shumë të vegjël anashkalohen |
| | Min SL × spread | 4 | spread-i ≤ 25% e rrezikut |
| | Min sweep | 10% e range-it | sweep-et prej disa centësh anashkalohen |
| | Max spread | 0.50 $ | |
| 5. SESSION | Session | 10:00–20:00 (ora e serverit) | Londër + New York |
| 6–9 | Motori, 1M micro, paneli, optimizimi | – | nuk kanë nevojë për ndryshim |

## Kufizimet

- Nuk ka filtër lajmesh (NFP, CPI, FOMC). Gjatë lajmeve ari lëviz shumë,
  ndaj përdor `InpUseSession` ose fike EA-në manualisht.
- Orari i sesionit është në kohën e serverit të brokerit, zakonisht GMT+2/+3.
- Mbahet vetëm një pozicion njëherësh për çdo simbol dhe magic number.
- Rezultatet e backtest-it nuk garantojnë fitim. Testoje fillimisht në llogari demo.

## Optimizimi (v1.23): testi i organizuar

Skedari `Presets/CRT_MTF_EA_optimize.set` përmban matricën e testit:

| Parametri | Vlerat që testohen |
|---|---|
| `InpEntryTF` | M5, M15, M30, H1 |
| `InpBiasMode` | Off, "Block against", "Same direction" |
| `InpBiasTF` | H1, H4 (duhet të jetë mbi timeframe-in e hyrjes) |
| `InpCloseOnInvalid` | true, false |
| `InpBreakEvenR` | 0 (fikur), 1.0 |

Janë 72 kombinime të vlefshme. Kombinimet e pavlefshme (M6, M10, H2 etj.)
anashkalohen menjëherë.

**Hapat:**
1. Kopjo `CRT_MTF_EA_optimize.set` te `MQL5/Profiles/Tester/`.
2. Strategy Tester → **Settings**:
   - Expert: `CRT_MTF_EA`, Symbol: XAUUSD, Timeframe: M5
   - Date: **2023.01.01 – 2026.09.26**
   - **Forward: Custom, 2025.07.01**. Periudha para kësaj date përdoret për zgjedhjen,
     ajo pas saj për vërtetim.
   - Modeling: **1 minute OHLC**
   - Optimization: **Slow complete algorithm**, kriteri: **Custom max**
     (profit factor, vetëm për kombinimet me ≥ 100 trade)
3. **Inputs** → klik i djathtë → **Load** → `CRT_MTF_EA_optimize.set`
4. **Start**. Kur të mbarojë, dërgo skedat **Optimization Results** dhe **Forward Results**.

**Si lexohet:** një kombinim ia vlen vetëm nëse ka **PF > 1.1 edhe në periudhën
forward** dhe të paktën 100 trade. Një PF i mirë vetëm në periudhën e parë
nuk mjafton: mund të jetë thjesht përshtatje me të kaluarën.

## Rezultatet e optimizimit dhe kandidati v1.25

Optimizimi 2 (vetëm "Require an active HTF CRT in the same direction"):

| Hyrja | Bias | Periudha 1 (2023 – qershor 2025) | Forward (korrik 2025 – shtator 2026) |
|---|---|---|---|
| M15 | D1 | PF 0.87 (306 trade) | **PF 1.39–1.41** (~185 trade) |
| H1 | D1 | PF 0.91–0.94 (103 trade) | PF 1.36–1.71 (39 trade) |
| H1 | H4 | PF 0.85–0.89 (112 trade) | PF 1.44–1.45 (47 trade) |
| M30 | H4/D1 | PF 0.62–0.79 | PF 0.83–1.09 |

- Çdo variant M15/H1 me bias H4/D1 në të njëjtin drejtim **humbi në periudhën 1
  dhe fitoi në forward**. Avantazhi varet nga kushtet e tregut (regjimi).
- Asnjë kombinim nuk e kaloi rregullin "PF ≥ 1.0 në periudhën 1".
- Parazgjedhjet e v1.25 janë familja më e mirë: **M15 + D1 same direction**.
  Përdore **vetëm në demo** derisa ta vërtetojmë.

---

# Testi i "CRT_MTF_MT5_TEST_V3" (kod i jashtëm, 5M CRT)

Rregullat e tregtimit të V3: hyrje me çmim tregu pas çdo CRT 5M të konfirmuar, SL te ekstremi i sweep-it
pa buffer, TP te ana tjetër e parent-it, pa filtra, 0.01 lot. U testua me `backtest/crt_backtest.py`
dhe historikun e FP Trading:

| Të dhënat | Trade | Në ditë | Win | PF | Mesatarja | 0.01 lot |
|---|---|---|---|---|---|---|
| M1, 2026.06–2026.10 (më i sakti) | 3 579 | 41 | 38.8% | 0.81 | −0.12R | −1 031 $ |
| M5, 2025.05–2026.10 | 17 749 | 40 | 37.9% | 0.77 | −0.15R | −4 713 $ |
| Të njëjtat rregulla, CRT M15 (2022–26) | 16 711 | 13 | 37.1% | 0.82 | −0.12R | −2 546 $ |
| Të njëjtat rregulla, CRT H1 (2022–26) | 3 680 | 3 | 36.9% | 0.89 | −0.07R | −979 $ |

Humb në çdo timeframe dhe në të dy gjysmat. Është e njëjta qasje si CRT_MTF_EA v1.10. SL mesatar është rreth 2.3 $,
prandaj spread-i (~0.2 $) merr ~10% të rrezikut në rreth 40 trade në ditë.

### Përmirësimet e provuara mbi V3

U testuan 32 kombinime mbi hyrjen e V3, d.m.th. hyrjen në mbylljen e CRT:
- filtrat e kostos (SL buffer 0.30, SL min 1 $ / 4× spread, spread max 0.50, sweep min 10%);
- trendi ditor SMA 50;
- CRT H4 ose D1 në të njëjtin drejtim;
- sesioni 01–13 NY;
- TP min 2R;
- hyrje në M5, M15 dhe H1.

| Më të mirat | Trade | PF (gjysma 1 / 2) |
|---|---|---|
| M5 + kosto + trend + CRT H4 + sesion (2025–26) | 520 | 1.03 (1.13 / 0.94) |
| M15 + kosto + trend + sesion + TP ≥ 2R (2022–26) | 543 | 1.05 (1.05 / 1.05) |
| **CRT_1AM_EA Combined (MT5, 2023–26)** | 788 | **1.37** |

Edhe me të gjitha filtrat, hyrja në mbylljen e CRT mbetet afër zeros. Avantazhi i CRT_1AM_EA vjen nga
hyrja te thyerja e OB në M15, brenda strukturës kohore H4, në drejtimin e trendit.

---

# CRT PRO24 (MT5): versioni 24 orë, pa orare fikse

Skedari: `Experts/CRT_1AM_PRO24.mq5` (v1.02). Është EA më vete; `CRT_1AM_EA.mq5` nuk preket.

- Ndjek **të 6 qirinjtë H4** të ditës (1AM, 5AM, 9AM, 1PM, 5PM, 9PM New York).
- Hyn **kur vjen setup-i**, në çfarëdo ore: sweep i range-it, pastaj një qiri M15 mbyllet përtej qiririt
  që bëri sweep-in dhe brenda range-it.
- Nuk ka key time, pauzë lajmesh apo dalje me orë.
- Filtrat: trendi ditor (mesatarja 50-ditore) dhe premium/discount i range-it.
- Dalja: SL përtej sweep-it, TP 1:2, mbyllje pas 8 orësh.
- E premtja në 16:00 NY mbyll trade-t (mbrojtje nga gap-i i fundjavës, `InpFridayClose = 0` e fik).
- Magic **770100**, pra mund të punojë krah CRT_1AM_EA (660100/660101).

### Si u zgjodh

U testuan kombinime pa orare fikse, me zgjedhje në 2022.07–2024.06 dhe kontroll në 2024.07–2026.09
dhe në 2020–2022 (M30):
- Hyrja M15 ose M30, OHLC on/off, trendi 50 ose 100 ditë: dallime të vogla.
- **Filtri i madhësisë së range-it** (ndaj ATR), që do të hiqte vetë qirinjtë e qetë si Asia: nuk qëndron.
- **Filtri i qiririt të lajmeve** (spike > 2–3× mesatarja), që do të zëvendësonte pauzën 8–10: nuk qëndron.
  Konfigurimet më të mira të periudhës së parë ranë në PF 1.05–1.07 në të dytën.
- **CRT mbi qirinjtë H1** (24 në ditë): humbës, PF 0.82–1.01. Hyrja M5: nuk përmirëson.

U mbajt varianti më i thjeshtë dhe më i qëndrueshëm.

### Rezultati (simulim, 2023.01.01–2026.09.26)

| | Trade | Win | PF | Total | Max DD | Fitimi |
|---|---|---|---|---|---|---|
| **PRO24, 0.5% rrezik** | 1226 | 42.6% | 1.17 | +112R | 11.1% | +71% |
| PRO24, 0.3% rrezik | 1226 | 42.6% | 1.17 | +112R | 6.8% | +39% |
| CRT_1AM_EA Combined, 0.5% | 787 | 47.0% | 1.40 | +151R | 6.5% | +109% |

PRO24 është pozitiv çdo vit (2023 +44R, 2024 +15R, 2025 +42R, 2026 +11R). Ka më shumë trade,
por më pak fitim për trade dhe rreth dyfish më shumë drawdown se versioni me orare.
Për të njëjtin drawdown si Combined, përdor rreth **0.3%** rrezik.

### v1.02: hyrje me retest (limit te niveli i OB-së)

Kur një qiri M15 thyen OB-në, PRO24 nuk hyn më menjëherë. Pret deri në **4 orë** që çmimi të kthehet
te niveli i OB-së dhe hyn aty. Nëse çmimi kalon përtej sweep-it para kësaj, setup-i anulohet.
`InpEntryType = Market` e kthen sjelljen e vjetër.

Kombinime të tjera të testuara, me zgjedhje në një periudhë dhe kontroll në 2024–26 dhe 2020–22 (M30):
- **CRT ditore** (sweep i high/low të djeshëm, hyrje me OB në M15/M30/H1): pa avantazh, negative në 2020–22.
- **Retest te Selective**: më keq.
- **Retest te Active / PRO24**: më mirë në të tre periudhat, për çdo kohë pritjeje 1–8 orë.

| PRO24, mesatarja për trade | 2022.07–24.06 | 2024.07–26.09 | 2020–22 (M30) |
|---|---|---|---|
| hyrje market (v1.01) | +0.075R | +0.080R | +0.042R |
| **retest 4 orë (v1.02)** | **+0.148R** | **+0.128R** | **+0.098R** |

Për periudhën e testit në MT5 (2023.01.01–2026.09.26, 0.5% rrezik):

| | Trade | PF | Fitimi | Max DD |
|---|---|---|---|---|
| PRO24 v1.01 (market) | 1226 | 1.17 | +71% | 11.1% |
| **PRO24 v1.02 (retest)** | **922** | **1.29** | **+107%** | **9.8%** |
| CRT_1AM_EA Combined | 787 | 1.40 | +109% | 6.5% |

Retest-i heq kryesisht humbjet "kthim i menjëhershëm" (L1): nga 192 në 67.

### Ditari i trade-ve dhe pse humbet (PRO24 v1.01)

**Në MT5:** PRO24 shkruan çdo trade të mbyllur te
`Common\Files\CRT_PRO24_journal.csv` (`InpJournal = true`). Në fund të testit, Journal tregon rrugën e plotë.
Gjen dosjen edhe nga MT5: File → Open Data Folder, pastaj dy nivele lart → `Common\Files`.
Në tester skedari rishkruhet në çdo test; në demo/live trade-t e reja shtohen në fund.

**Në Python:** `backtest/loss_report.py` bën të njëjtën gjë me historikun e brokerit:
```
python3 loss_report.py --mt5 ../data/XAUUSD_M15.csv --mode pro24      # ose combined / active / selective
```
Rezultatet janë te `reports/pro24_trades.csv` dhe `reports/combined_trades.csv`.

Kolonat e skedarit:
- koha (server dhe NY), dita, qiriri H4, drejtimi;
- entry/SL/TP, SL në $, rezultati në R, dalja, minutat;
- **max në favor** dhe **max kundër** (në R): sa shkoi trade-i për ne dhe kundër nesh;
- range-i, sweep-i, pozicioni i hyrjes në range, trendi, SL/ATR, spread-i;
- **lloji** i fitimit/humbjes dhe një **përshkrim**.

| Lloji | Kuptimi |
|---|---|
| L1 | kthim i menjëhershëm: SL brenda 1 ore, pa lëvizje në favor (sweep-i vazhdoi) |
| L2 | pa drejtim: SL pas më shumë se 1 ore, pa lëvizje në favor |
| L3 | lëvizje e vogël në favor (+0.3R deri +1R), pastaj SL |
| L4 | fitim i humbur: arriti +1R e më shumë, pastaj SL |
| L5 | mbyllje me kohë në humbje |
| W1 / W2 | TP / mbyllje me kohë në fitim |

Rezultati për PRO24 (2023.01–2026.09, 1226 trade):
- L3 232 trade, L1 192, L4 120, L2 88, L5 72;
- W1 316 trade, W2 206.

Rregullat e testuara kundër këtyre humbjeve, me kontroll në të dy gjysmat dhe në 2020–2022:
- mbyllja e 50% në +1R me break-even (për L4);
- pa sweep-e më të thella se 50% e range-it;
- pa hyrje të premten;
- pa qiririn 9PM.

**Asnjë nuk qëndron:** ndihmon një periudhë dhe dëmton një tjetër. Humbjet janë kryesisht pjesë e natyrshme e strategjisë.
Ditari i demo-s do tregojë nëse në tregun live shfaqet ndonjë model i ri.

---

# CRT 1AM EA (MT5): strategjia nga PDF-të "1AM CRT" dhe "Time & Price"

Skedari: `Experts/CRT_1AM_EA.mq5` (v1.05). Është EA e re, e veçantë nga CRT_MTF_EA.
Nuk hap trade në çdo CRT, por vetëm në qiririn H4 të orës **1:00 New York** dhe
vetëm në orën kyçe.

## Rregullat e PDF-ve dhe si janë në EA

| Rregulli në PDF | Në EA | Input |
|---|---|---|
| Bias nga HTF (drejtimi ditor, DOL) | Trendi ditor: mbyllja e djeshme mbi mesataren 50-ditore = vetëm buy, nën të = vetëm sell | `InpBias`, `InpTrendDays` |
| Range-i kohor: qirinjtë 5PM + 9PM (Asia/CBDR) | High/low i 17:00–01:00 NY | automatik |
| Qiriri 1AM bën sweep të high/low të range-it (turtle soup) | Ndiqet çdo qiri M15 brenda 01:00–05:00 NY | automatik |
| OHLC / OLHC: sell mbi open, buy nën open | Sell vetëm kur çmimi është mbi open-in e qiririt 1AM | `InpOHLC` |
| Premium / discount | Sell vetëm mbi mesin e range-it kohor (Asia), buy vetëm poshtë tij | `InpPremDisc` |
| Ora kyçe 2:00–4:00 AM NY | Sinjali pranohet vetëm në këtë orar | `InpKT1From`, `InpKT1To` |
| Hyrja, modeli #1: qiriri që "gërmoi" mbi high-in, pastaj engulf | Qiriri me high-in më të lartë është OB; hyrje kur një qiri mbyllet nën low-in e tij dhe brenda range-it. Timeframe-i i hyrjes: **M30** (M15 si opsion) | `InpEntryTF` |
| SL përtej sweep-it | SL = maja e sweep-it + 0.30 $ | `InpSLBuffer` |
| TP 1:2 ose 1:3 | TP = 2R (mund ta bësh 3) ose ana tjetër e range-it | `InpTPMode`, `InpRR` |
| Modelet 5AM dhe 9AM (forex key times) | Të ndezura; maksimumi 1 trade në ditë për të tre modelet | `InpModel5AM`, `InpModel9AM` |

Nuk janë në EA: **SMT** (duhet simbol i dytë, p.sh. XAGUSD) dhe nivelet kyçe H4
(OB/FVG). Filtri premium/discount i zëvendëson pjesërisht.

## Ora e New York-ut (e rëndësishme)

EA-ja i llogarit të gjitha oraret në kohën e New York-ut:
`ora NY = ora e serverit − InpNYOffset`.

- Te shumica e brokerëve MT5 serveri është **NY + 7** gjatë gjithë vitit (GMT+2 në dimër,
  GMT+3 në verë), prandaj vlera fillestare është **7**.
- Kontroll: në MT5 hape **Market Watch**; ora lart është ora e serverit. Kur në New York
  është 00:00, serveri duhet të tregojë 07:00. Nëse jo, ndryshoje `InpNYOffset`.
- Te paneli i EA-së shfaqet "New York time"; duhet të përputhet me orën reale të NY.

## v1.05: a duhen oraret? Mënyra "Any time" (24h)

Testi i v1.04 Combined në MT5 (2023.01.01–2026.09.26): 788 trade, PF 1.37, +97%, DD 7.0%.
Rezultati ndahet në Active +115.5R dhe Selective +24.7R. Simulimi priste 787 trade dhe PF 1.40.

Pyetja ishte: a mund të hyjë EA-ja kur vjen setup-i, pa orare fikse? Mënyra e re
`InpMode = Any time` merr setup-in në **të 6 qirinjtë H4 të ditës** (edhe 5PM dhe 9PM, pra 24 orë),
pa key time dhe pa pauzën e lajmeve. Testi (2023.01.01–2026.09.26, 0.5% rrezik):

| | Trade | PF | Total | Max DD | Fitimi |
|---|---|---|---|---|---|
| **Combined (me orare)** | 787 | **1.40** | +151R | **13.3R** | **+109%** |
| Any time (24h) | 1226 | 1.17 | +112R | 23.4R | +71% |

Edhe në 2020–2022 (M30, të pavarura) "çdo orë" del më keq: PF 1.08 kundrejt 1.20.
Qirinjtë 5PM dhe 9PM nuk japin rezultat të qëndrueshëm: dalin pozitivë në një periudhë dhe negativë në tjetrën.
Rregulli i vetëm kohor që ndihmon gjithmonë është pauza e lajmeve 8:00–10:00 NY.

Oraret nuk janë hyrje me orë fikse. Brenda çdo qiriri H4, EA-ja hyn kur vjen setup-i
(sweep + thyerje e OB), në çdo minutë. Oraret vetëm tregojnë cilat qirinj H4 ndiqen.
Kjo është ideja e "Time & Price" te PDF-të.

## v1.04: mënyra Combined dhe pa hyrje në orën e lajmeve

Testi në MT5 i v1.03 Active (2023.01.01–2026.09.26) dha 857 trade, PF 1.21, +57%, DD 7.1%.
Simulatori për të njëjtën periudhë jep 856 trade dhe PF 1.25, pra EA-ja dhe simulatori përputhen.

Kërkesa e radhës ishte një kurbë më e rregullt. U testuan 12 ide. Dy kaluan edhe në të dhënat e
pavarura 2020–2022 (M30), që nuk u përdorën për t'i gjetur:

1. **Pa hyrje të reja 08:00–10:00 NY** (lajmet e SHBA-së në 8:30). Në 2020–2022 DD ra nga 18.5R në 12.7R.
2. **Active + Selective në të njëjtën EA** (`InpMode = Combined`). Secila ka magic-un e vet
   (Selective = magic + 1), pra mund të jenë hapur deri në 2 pozicione njëkohësisht.

Nuk kaluan dhe nuk u futën: break-even, TP 1.5, mbajtja 6/12 orë, kufiri 2–3 trade në ditë,
trendi i dyfishtë (50 & 20 / 50 & 100), kufiri i SL ndaj ATR dhe filtri i së enjtes.

Simulimi për 2023.01.01–2026.09.26 me 0.5% rrezik për trade:

| | Trade | Win | PF | Total | Max DD | Muaj pozitivë | Fitimi |
|---|---|---|---|---|---|---|---|
| v1.03 Active | 856 | 44.6% | 1.25 | +109R | 13.4R | 27/45 | +69% |
| v1.04 Active | 744 | 46.2% | 1.35 | +126R | 11.6R | 31/45 | +85% |
| **v1.04 Combined** | **787** | **47.0%** | **1.40** | **+151R** | **13.3R** | **33/45** | **+109%** |

Llogaria duhet të jetë **hedging**, që dy pozicionet të mos bashkohen në një.

## Laboratori i modeleve (`backtest/model_lab.py`): 52 kombinime

U testuan 52 modele në disa timeframe, me historikun M30 2020.02–2026.09 dhe kosto
= spread-i i brokerit + 0.10 $:
- **CRT klasik** (motori i CRT_MTF_EA) në M30, H1, H4, me dhe pa trend, me sesion ose gjithë ditën,
  me TP te target-i ose 1:2;
- **sweep i high/low të ditës së kaluar** (turtle soup) në M30 dhe H1;
- **breakout i range-it Asia** në drejtimin e daljes;
- **modeli H4 i PDF-ve** (Active dhe Selective, me dhe pa trend).

Rregulli: modelet zgjidhen **vetëm** me 2020.02–2023.06, pastaj gjykohen me 2023.07–2026.09.

| Familja | Rezultati |
|---|---|
| CRT klasik M30 / H1 / H4 (24 variante) | humbin: PF 0.77–1.06 |
| Sweep i ditës së kaluar (8) | humbin: PF 0.79–1.01 |
| Breakout Asia (16) | afër zeros: PF 0.82–1.13, humbës në periudhën e parë |
| **Modeli H4 i PDF-ve** | **i vetmi që kalon**; 3 variante, të tre pozitive edhe në periudhën e panjohur |

Kombinimi i modeleve humbëse nuk krijon fitim. Kombinimi i dobishëm është
**Active + Selective njëkohësisht**, në dy grafikë me magic number të ndryshëm.
Rezultati mbi M15 2022.10–2026.09, me spread +0.10 $:

| | Trade në ditë | Mesatarja | PF | R në vit | Max DD |
|---|---|---|---|---|---|
| Active | 0.92 | +0.10R | 1.19 | 22.8 | 13.5R |
| **Active + Selective** | **0.96** | **+0.12R** | **1.23** | **28.0** | **14.5R** |

Shënim: modeli H4 u ndërtua duke parë të gjithë periudhën, prandaj për të "periudha e panjohur"
nuk është plotësisht e panjohur. Për 49 modelet e tjera testi është i pastër.

## v1.03: dy mënyra, Active dhe Selective (`InpMode`)

Kërkesa ishte 4–5 trade në ditë. Testi me historikun real tregon se kjo metodë nuk i jep:
- Edhe me çdo qiri H4 dhe pa asnjë filtër, sinjalet dalin rreth 1.5–1.9 në ditë në M5 dhe 0.9–1.5 në M15.
- Pa filtrat ato humbin (−0.02R deri −0.05R për trade).
- Sa më shumë trade, aq më i dobët është çdo trade.

Mënyra më aktive që fiton ende është **Active** dhe është vlera fillestare:

| | Active (fillestare) | Selective |
|---|---|---|
| Qirinjtë H4 | 1AM, 5AM, 9AM, 1PM, gjithë qiriri | 1AM 2–4, 5AM 5–7, 9AM 9:30–11 |
| Hyrja | M15 | M30 |
| Rregulli OHLC | jo | po |
| Dalja | SL/TP ose pas 8 orësh | SL/TP ose në 12:00 NY |
| Trade në ditë | deri 5 (një njëherësh) | 1 |
| E përbashkët | trend 50 ditë, premium/discount, TP 1:2, mbyllje të premten në 16:00 NY | |

Rezultatet (simulim me historikun e FP Trading, 0.5% rrezik për trade):

| | Periudha | Trade | Në javë | Win | PF | Max DD | Fitimi |
|---|---|---|---|---|---|---|---|
| **Active** | 2022.07–2026.09 (M15) | 932 | ~4 | 44% | 1.23 | 13.4R | +72% |
| Active, rregullat në M30 | 2020.02–2026.09 | 842 | ~2.5 | 45% | 1.19 | 18.1R | çdo vit + |
| **Selective** | 2020.02–2026.09 (M30) | 74 | ~0.2 | 55% | 2.17 | 6.2R | +19.7% |

- **Active** është pozitiv çdo vit (2022 +5R, 2023 +34R, 2024 +21R, 2025 +43R, 2026 +8R).
  Avantazhi vjen nga **trendi ditor**: pa të, Active humb (−0.02R). Në një vit pa trend, prit rezultat afër zeros.
- Avantazhi për trade është i hollë (+0.12R), por mbetet pozitiv edhe me spread +0.30 $ (PF 1.12).
- Seria më e gjatë e humbjeve në Active është 11 trade radhazi (≈ −5.5% me 0.5% rrezik).

## v1.02: testi me historikun real të FP Trading (2020–2026)

Të dhënat: eksportet MT5 të llogarisë demo (M30/H1/H4/D1 nga 2020.02, M15 nga 2022.07,
M5 nga 2025.05). Ora e serverit u verifikua: java hapet të hënën 01:00, dita mbyllet 00:00,
pra **server = New York + 7**.

Çfarë tregoi testi:
- v1.01 (M15, bias CRT ditore/dita e kaluar) mbi M15 2022–2026: 113 trade, **PF 1.00**. Blerjet
  fitonin (+0.22R), shitjet humbnin (−0.30R): ari ishte në trend, jo avantazh i CRT-së.
- Hyrja **M30** jep sinjale më të pastra se M15, dhe **filtri i trendit ditor** (mesatarja 50-ditore)
  e përmirëson ndjeshëm. Filtri **OHLC** i PDF-së është filtri më i rëndësishëm (pa të: +0.15R, me të: +0.49R).

v1.02 (vlerat fillestare) mbi XAUUSD M30, 2020.02 – 2026.09, spread-i i brokerit:

| Periudha | Trade | Win | Mesatarja | PF | Max DD | Fitimi me 0.5% rrezik |
|---|---|---|---|---|---|---|
| 2020–2023 | 48 | 50% | +0.37R | 1.82 | 6.2R | +9.2% |
| 2024–2026 | 26 | 65% | +0.71R | 3.04 | 3.0R | +9.5% |
| **Gjithsej** | **74** | **55%** | **+0.49R** | **2.17** | **6.2R** | **+19.7%** |

Çdo vit 2020–2026 doli pozitiv. Variantet përreth (trend 20/100 ditë, RR 1.5/3, pa premium/discount,
vetëm 1AM, hyrje M15) dalin të gjitha pozitive në të dy periudhat, pra rezultati nuk varet nga një
vlerë e vetme. Me spread +0.50 $ më të gjerë, PF bie në 1.42.

**Kujdes:**
- Rreth 11 trade në vit. Është strategji e rrallë dhe fitimi është i vogël por i qëndrueshëm.
- Konfigurimi u zgjodh duke parë të gjithë periudhën 2020–2026. Prova e vërtetë është demo live.
- Rezultati i MT5 Tester mund të ndryshojë pak nga simulimi (modeli i spread-it dhe i tick-eve).

## v1.01: pse v1.00 nuk dha asnjë hyrje

v1.00 kishte njëkohësisht tre filtra shumë të ngushtë:
- tregtonte vetëm kur kishte CRT ditore aktive (rreth 60% e ditëve nuk kanë);
- premium/discount i matur me ditën e kaluar;
- qiriri që bënte engulf dhe njëkohësisht një high/low të ri nuk llogaritej si hyrje.

Në simulim me të dhëna që imitojnë orarin e arit (3.7 vjet), v1.00 jep rreth 22 trade,
pra afërsisht një në 2 muaj. v1.01 jep rreth 110 trade, pra afërsisht një në javë:
- bias: CRT ditore, dhe kur nuk ka, qiriri ditor i kaluar;
- premium/discount: mesi i range-it Asia;
- engulf-i me high/low të ri tani llogaritet.

Në fund të çdo testi, Journal shfaq dy rreshta (shembull nga simulimi):

```
CRT 1AM FUNNEL: CRT candles 975 | no data 1 | no bias 0 | high sweeps 686 | low sweeps 664 | OB breaks 1229 | trades 111
CRT 1AM REJECTED: key time 448 | against bias 408 | OHLC 232 | premium/discount 30
```

Këta tregojnë sa qirinj 1AM u panë, sa sweep dhe sa OB break pati, si dhe cili filtër bllokoi
sa sinjale. Nëse del "no data" i madh, mungon historia; nëse "key time" është i madh,
kontrollo `InpNYOffset`.

## Testimi

1. Kopjo `Experts/CRT_1AM_EA.mq5` te `MQL5/Experts/`, hape në MetaEditor, **F7**.
2. Strategy Tester:
   - Expert: `CRT_1AM_EA`, Symbol: XAUUSD, Timeframe: M15
   - Date: **2023.01.01 – 2026.09.26**, Forward: **No**
   - Modeling: **1 minute OHLC**
   - `InpMode`: **Combined** (fillestare), Active, Selective ose Custom
3. Te **Inputs**: klik i djathtë → **Reset**. Mos ndrysho asgjë në provën e parë.
4. Pas testit dërgo skedën **Backtest** dhe rreshtat `CRT 1AM FUNNEL`, `CRT 1AM REJECTED`
   dhe `CRT 1AM SUMMARY` nga **Journal**.

Pastaj mund të krahasohen variantet me optimizim (Custom max):
`InpBias` (5 vlera), `InpTrendDays` (20, 50, 100), `InpEntryTF` (M15, M30), `InpRR` (1.5, 2, 3).

## Simulatori offline

`backtest/crt_1am_backtest.py` përdor të njëjtat rregulla mbi eksportet MT5
(`python3 crt_1am_backtest.py --mt5 ../data/XAUUSD_M30.csv`).
Te random walk (pa spread) mesatarja është rreth 0R (5 867 trade, −0.005R ± 0.016),
pra simulatori nuk krijon fitim ose humbje fallco. Eksportet vendosen te `data/`
(Ctrl+U → Bars → XAUUSD → Request → Export). Dosja `data/` nuk ruhet në git.
