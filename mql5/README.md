# KalmanVolumeXAU: EA për MetaTrader 5

EA për **XAUUSD** i ndërtuar mbi parashikimin e vëllimit me filtër Kalman (Chen, Feng & Palomar, SSRN 3101695). Të tre mënyrat e përdorimit janë bashkuar në një EA. Çdo modul ndizet ose fiket veçmas, kështu që EA-ja mund të përdoret edhe si "një EA për secilin modul".

> ⚠️ **Lexo [`analysis/XAUUSD_ANALIZA.md`](../analysis/XAUUSD_ANALIZA.md) para përdorimit.** Në 4 vjet të dhëna XAUUSD M15 asnjë kombinim nuk doli fitimprurës në mënyrë të qëndrueshme pas kostove. Përdore vetëm në Strategy Tester ose në demo.

## Skedarët

| Skedari | Ku vendoset në MT5 |
|---|---|
| `Include/KalmanVolume.mqh` | `MQL5/Include/KalmanVolume.mqh` |
| `Experts/KalmanVolumeXAU.mq5` | `MQL5/Experts/KalmanVolumeXAU.mq5` |

## Instalimi

1. Në MT5: **File → Open Data Folder**.
2. Kopjo dy skedarët në dosjet e tabelës më sipër.
3. Hap `KalmanVolumeXAU.mq5` në MetaEditor dhe shtyp **F7** (Compile). Duhet të dalë "0 errors".
4. Hap grafikun **XAUUSD M15** dhe tërhiq EA-në mbi të.
5. Në tab-in "Common", aktivizo "Allow Algo Trading".

## Testi në Strategy Tester

| Fusha | Vlera |
|---|---|
| Expert | KalmanVolumeXAU |
| Symbol / Period | XAUUSD / M15 |
| Modeling | Every tick based on real ticks |
| Data | P.sh. 2023.01.01 – 2026.09.30 |

**Kujdes me fillimin e testit:** modeli kërkon 60 ditë histori para çdo dite. Nëse journal-i shkruan "vetem X dite te vlefshme", vendos datën e fillimit të paktën 3 muaj pas fillimit të historisë që ka broker-i.

Krahaso rezultatin me tabelën e seksionit 4 te raporti. Për Donchian + B + C, në backtest-in Python (OOS 07.2025–09.2026, me +10 pikë kosto) pritet:
- ~600 tregti;
- PF ~1.0.

## Si funksionon

### Modeli

Çdo ditë të re EA-ja:
1. Merr 60 ditët e fundit të plota të bar-eve.
2. Ndërton rrjetin 92 bar-e/ditë (01:00–24:00 me orën e serverit).
3. Kalibron modelin me EM.

Pastaj, me çdo bar të mbyllur, filtri Kalman përditëson:
- **η:** niveli i vëllimit të ditës;
- **μ:** dinamika brenda ditës;
- **parashikimin** e bar-eve të ardhshme.

Bërthama (`KalmanVolume.mqh`) është testuar kundrejt implementimit Python. Përputhen deri në 2·10⁻¹⁶ (`tests/test_mql_core.py`).

### Hyrja bazë (`InpTrigger`)

| Opsioni | Rregulli |
|---|---|
| Breakout Donchian | Mbyllja kalon max/min e N bar-eve të mëparshme |
| Momentum | Trupi i bar-it ≥ `InpBodyATR` × ATR, hyrje në drejtimin e bar-it |
| Fade | I njëjti bar, hyrje në drejtimin e kundërt |

### Modulet

| Moduli | Çfarë bën | Çfarë thonë të dhënat | Default |
|---|---|---|---|
| **A: volume surprise** | Hyn vetëm kur `z = log(vëllimi real / parashikimi) / σ` është mes `InpA_MinZ` dhe `InpA_MaxZ` | Me breakout/momentum **dëmton**. Me Fade: IS PF 1.13, OOS PF 0.95 | OFF |
| **B: hyrje e ndarë (VWAP)** | Pozicioni ndërtohet në `InpB_Slices` bar-e. Çdo copë = pjesa e mbetur × vëllimi i bar-it tjetër / vëllimi i copave të mbetura (ek. 41 e artikullit). Copat e mbetura anulohen nëse preket SL/TP | Ul drawdown-in në OOS; efekti në rezultat i përzier | ON |
| **C: regjimi i vëllimit** | (1) Hyrje vetëm kur aktiviteti i ditës (η) është mes `InpC_ActMin` dhe `InpC_ActMax`. (2) SL = `InpSL_ATR` × ATR × (vëllimi i pritshëm i `InpC_Horizon` bar-eve / vëllimi i 14 bar-eve të fundit)^`InpC_Beta`, i kufizuar mes `InpC_AdjMin` dhe `InpC_AdjMax` | Përmirëson të tri hyrjet bazë (pa A), IS dhe OOS | ON |

### Rreziku dhe daljet

| Parametri | Kuptimi |
|---|---|
| `InpRiskPercent` | % e equity që rrezikohet për tregti. Lot-et llogariten nga distanca e SL dhe vlera e tick-ut |
| `InpRR` | TP = RR × distanca e SL |
| `InpMaxHoldBars` | Mbyll pas kaq bar-esh |
| `InpFlatAt` | Mbyll gjithçka, p.sh. në 23:30, para rollover-it me spread të gjerë |
| `InpMaxSpreadPts` | Nuk hyn kur spread-i është më i madh |
| `InpMaxTradesDay` | Max sinjale në ditë |

### Sesioni

`InpSessionStart` / `InpSessionEnd` janë me orën e **serverit** të broker-it. Vlerat default 0100–2400 vlejnë për broker-in e të dhënave të testit. Nëse broker-i yt e hap arin në një orë tjetër, ndryshoji. Rrjeti duhet të ndahet saktë me timeframe-in.

## Paneli në grafik

EA-ja shfaq në cep të grafikut:
- parametrat e modelit;
- raportin vëllim/parashikim të bar-it të fundit (dhe z-score-in);
- aktivitetin e ditës;
- shumëzuesin e SL nga moduli C.

Në journal regjistrohet çdo rifitim ditor.
