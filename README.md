# Raporti i Analizave – ditar tregtimi

`Raporti_i_Analizave.xlsx` – raport i gatshëm (Excel / Google Sheets) për të mbajtur shënimet e trade-ve:
statistikat (Total Trades / WINS / LOSS / BE, Winrate, PnL), grafikët e Balance dhe tabela me statuset me ngjyra.

- Plotëso vetëm: **Data, Pair, Setup, R:R, Status i pozitës** (dhe **Shënime** nëse do).
- Rreziku për trade dhe vlerat e statuseve ndryshohen te fleta **Cilësimet**.
- Udhëzimet e plota janë te fleta **Udhëzime**.

**Lidhja automatike me cTrader:** trade-t e mbyllura shkruhen vetë te raporti. Shih [`ctrader/UDHEZIME.md`](ctrader/UDHEZIME.md).

Për ta rikrijuar skedarin: `python3 build_raporti.py`
