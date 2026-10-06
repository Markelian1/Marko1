# Marko1: robot tregtimi mbi parashikimin Kalman të vëllimit

Bazuar në Chen, Feng & Palomar, *"Forecasting Intraday Trading Volume: A Kalman Filter Approach"* (SSRN 3101695), zbatuar te XAUUSD.

| Çfarë | Ku |
|---|---|
| Analiza e artikullit dhe e tabelave të tij | [`analysis/ANALIZA.md`](analysis/ANALIZA.md) |
| **Analiza e XAUUSD dhe testi i EA-së (lexo këtë)** | [`analysis/XAUUSD_ANALIZA.md`](analysis/XAUUSD_ANALIZA.md) |
| EA për MT5: instalimi dhe parametrat | [`mql5/README.md`](mql5/README.md) |
| Modeli Kalman + EM (Python, referencë) | [`model/kalman_volume.py`](model/kalman_volume.py) |
| Walk-forward mbi historinë MT5 | [`model/walkforward.py`](model/walkforward.py) |
| Backtest i rregullave të EA-së në Python | [`strategy/`](strategy/) |
| Teste: MQL5 vs Python, sintaksa e EA-së | [`tests/`](tests/) |
| Të dhënat XAUUSD (eksport MT5, gzip) | [`data/xauusd/`](data/xauusd/) |

## Rifitimi i rezultateve

```bash
pip install -r analysis/requirements.txt
python3 -I tests/test_mql_core.py          # bërthama MQL5 == Python
python3 -I tests/test_ea_compiles.py       # kontroll sintakse i EA-së me g++
python3 -I analysis/xauusd_eda.py          # analiza e të dhënave
python3 -I model/walkforward.py data/xauusd/XAUUSD_M15.csv.gz data/derived/m15_rkf.csv.gz   # ~12 min
python3 -I analysis/xauusd_model_eval.py   # (kërkon edhe m15_kf.csv.gz: --robust-k 0)
python3 -I analysis/xauusd_signal_research.py
python3 -I strategy/ablation.py
python3 -I strategy/grid_is_oos.py
```
