using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using cAlgo.API;

namespace cAlgo.Robots
{
    // Dërgon çdo trade të mbyllur te "Raporti i Analizave" në Google Sheets (përmes GoogleAppsScript.gs).
    [Robot(AccessRights = AccessRights.None, TimeZone = TimeZones.UTC)]
    public class RaportiSync : Robot
    {
        [Parameter("URL e Google Script", DefaultValue = "")]
        public string Url { get; set; }

        [Parameter("Token (fjalëkalimi)", DefaultValue = "")]
        public string Token { get; set; }

        [Parameter("Importo historinë (ditë)", DefaultValue = 0, MinValue = 0)]
        public int ImportDays { get; set; }

        [Parameter("Kufiri BE (R)", DefaultValue = 0.2, MinValue = 0, Step = 0.05)]
        public double BeThresholdR { get; set; }

        [Parameter("Kufiri BE pa SL (pips)", DefaultValue = 3, MinValue = 0)]
        public double BeThresholdPips { get; set; }

        private const LocalStorageScope Scope = LocalStorageScope.Type;

        private sealed class Levels { public double? Sl; public double? Tp; }
        private sealed class Waiting { public int Id; public DateTime ClosedAt; public int Tries; }
        private sealed class Outgoing { public int Id; public DateTime ClosedAt; public string Json; }

        // SL dhe TP fillestare të çdo pozicioni (para se SL të çohet në BE), për të llogaritur R:R.
        private readonly Dictionary<int, Levels> _levels = new Dictionary<int, Levels>();
        private readonly List<Waiting> _waiting = new List<Waiting>();
        private readonly List<Outgoing> _outbox = new List<Outgoing>();

        protected override void OnStart()
        {
            if (string.IsNullOrWhiteSpace(Url) || string.IsNullOrWhiteSpace(Token))
            {
                Print("Vendos 'URL e Google Script' dhe 'Token' te parametrat e cBot-it.");
                Stop();
                return;
            }

            LoadLevels();
            foreach (var position in Positions)
                Remember(position);

            Positions.Opened += args => Remember(args.Position);
            Positions.Modified += args => Remember(args.Position);
            Positions.Closed += args => _waiting.Add(new Waiting { Id = args.Position.Id, ClosedAt = Server.Time });

            CatchUp();
            Timer.Start(TimeSpan.FromSeconds(5));
            Print("RaportiSync u nis. Trade-t e mbyllura dërgohen automatikisht te Raporti.");
        }

        protected override void OnTimer()
        {
            // Prit derisa mbyllja të shfaqet në History (mund të vonojë disa sekonda).
            for (int i = _waiting.Count - 1; i >= 0; i--)
            {
                var w = _waiting[i];
                w.Tries++;
                var legs = Legs(w.Id);
                if (w.Tries >= 2 && legs.Count > 0 && legs[legs.Count - 1].ClosingTime >= w.ClosedAt.AddMinutes(-1))
                {
                    _outbox.Add(Build(legs));
                    _waiting.RemoveAt(i);
                }
                else if (w.Tries > 60)
                {
                    Print("Pozicioni #{0} nuk u gjet në History, nuk u dërgua.", w.Id);
                    _waiting.RemoveAt(i);
                }
            }

            _outbox.Sort((a, b) => a.ClosedAt.CompareTo(b.ClosedAt));
            while (_outbox.Count > 0)
            {
                var o = _outbox[0];
                if (!Send(o))
                    break; // provohet përsëri pas 5 sekondash, me të njëjtën radhë
                _outbox.RemoveAt(0);
                LocalStorage.SetString("lastSync", o.ClosedAt.Ticks.ToString(CultureInfo.InvariantCulture), Scope);
                _levels.Remove(o.Id);
                SaveLevels();
            }
        }

        // Trade-t që u mbyllën ndërkohë që cBot-i ishte i fikur (ose N ditët e fundit, nëse kërkohet).
        private void CatchUp()
        {
            DateTime since = Server.Time;
            long ticks;
            var saved = LocalStorage.GetString("lastSync", Scope);
            if (ImportDays > 0)
                since = Server.Time.AddDays(-ImportDays);
            else if (!string.IsNullOrEmpty(saved) && long.TryParse(saved, NumberStyles.Integer, CultureInfo.InvariantCulture, out ticks))
                since = new DateTime(ticks);
            else
                LocalStorage.SetString("lastSync", Server.Time.Ticks.ToString(CultureInfo.InvariantCulture), Scope);

            var openIds = new HashSet<int>(Positions.Select(p => p.Id));
            var closed = History
                .Where(t => !openIds.Contains(t.PositionId))
                .GroupBy(t => t.PositionId)
                .Select(g => g.OrderBy(t => t.ClosingTime).ToList())
                .Where(legs => legs[legs.Count - 1].ClosingTime > since);
            foreach (var legs in closed)
                _outbox.Add(Build(legs));
            if (_outbox.Count > 0)
                Print("{0} trade nga historia do të dërgohen te Raporti.", _outbox.Count);
        }

        private List<HistoricalTrade> Legs(int positionId)
        {
            return History.Where(t => t.PositionId == positionId).OrderBy(t => t.ClosingTime).ToList();
        }

        private Outgoing Build(List<HistoricalTrade> legs)
        {
            var first = legs[0];
            var last = legs[legs.Count - 1];
            int id = first.PositionId;
            double dir = first.TradeType == TradeType.Buy ? 1 : -1;
            double entry = first.EntryPrice;

            Levels lv;
            _levels.TryGetValue(id, out lv);
            double? rr = null;
            string result;
            if (lv != null && lv.Sl.HasValue)
            {
                double risk = Math.Abs(entry - lv.Sl.Value);
                if (lv.Tp.HasValue)
                    rr = Math.Round(Math.Abs(lv.Tp.Value - entry) / risk, 2);
                double r = (last.ClosingPrice - entry) * dir / risk;
                result = r > BeThresholdR ? "TP" : r < -BeThresholdR ? "LOSS" : "BE";
            }
            else
            {
                result = last.Pips > BeThresholdPips ? "TP" : last.Pips < -BeThresholdPips ? "LOSS" : "BE";
            }
            // Më shumë se një mbyllje = pozicioni u mbyll pjesërisht (close half).
            string status = legs.Count > 1 && result != "LOSS" ? "CLOSE HALF - " + result : result;

            double net = legs.Sum(t => t.NetProfit);
            double startBalance = first.Balance - first.NetProfit;
            double pct = startBalance > 0 ? net / startBalance * 100 : 0;
            double volume = legs.Sum(t => t.VolumeInUnits);
            double pips = volume > 0 ? legs.Sum(t => t.Pips * t.VolumeInUnits) / volume : last.Pips;
            string note = string.Format(CultureInfo.InvariantCulture,
                "cTrader #{0} | P/L {1:+0.00;-0.00} ({2:+0.00;-0.00}%) | {3:+0.0;-0.0} pips", id, net, pct, pips);

            string setup = !string.IsNullOrWhiteSpace(first.Comment) ? first.Comment : first.Label ?? "";
            var entryLocal = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(first.EntryTime, DateTimeKind.Utc), TimeZoneInfo.Local);

            var json = new StringBuilder()
                .Append("{\"token\":").Append(Quote(Token))
                .Append(",\"id\":").Append(Quote(id.ToString(CultureInfo.InvariantCulture)))
                .Append(",\"date\":").Append(Quote(entryLocal.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)))
                .Append(",\"pair\":").Append(Quote(Pair(first.SymbolName)))
                .Append(",\"setup\":").Append(Quote(setup.Trim().ToUpperInvariant()))
                .Append(",\"rr\":").Append(rr.HasValue ? rr.Value.ToString(CultureInfo.InvariantCulture) : "null")
                .Append(",\"status\":").Append(Quote(status))
                .Append(",\"note\":").Append(Quote(note))
                .Append('}');
            return new Outgoing { Id = id, ClosedAt = last.ClosingTime, Json = json.ToString() };
        }

        // true = u krye (mos e dërgo më), false = provo përsëri më vonë
        private bool Send(Outgoing o)
        {
            string body;
            int code;
            try
            {
                var response = Http.Send(new HttpRequest(new Uri(Url)) { Method = HttpMethod.Post, Body = o.Json });
                code = (int)response.StatusCode;
                body = response.Body ?? "";
                // Google e jep përgjigjen pas një ridrejtimi (302). Nëse nuk u ndoq vetë, ndiqe këtu.
                var link = RedirectLink(body);
                if (!body.Contains("\"ok\":") && link != null)
                {
                    var echo = Http.Get(link);
                    code = (int)echo.StatusCode;
                    body = echo.Body ?? "";
                }
            }
            catch (Exception e)
            {
                Print("Dërgimi dështoi: {0}. Do provohet përsëri.", e.Message);
                return false;
            }

            if (body.Contains("\"ok\":true"))
            {
                var row = Regex.Match(body, "\"row\":(\\d+)");
                if (row.Success)
                    Print("Pozicioni #{0} u shkrua te Raporti, rreshti {1}.", o.Id, row.Groups[1].Value);
                else
                    Print("Pozicioni #{0} ishte tashmë te Raporti.", o.Id);
                return true;
            }
            if (code >= 500 || code == 429)
            {
                Print("Google nuk u përgjigj (kodi {0}). Do provohet përsëri.", code);
                return false;
            }

            var error = Regex.Match(body, "\"error\":\"([^\"]*)\"");
            string reason = error.Success ? error.Groups[1].Value
                : code == 401 || code == 403
                    ? "kodi " + code + ": Google kërkon hyrje. Te Deploy vendos 'Who has access: Anyone' dhe përdor URL-në që mbaron me /exec"
                    : "kodi " + code + ", " + Snippet(body);
            Print("GABIM: pozicioni #{0} NUK u shkrua. Google: {1}", o.Id, reason);
            Print("Rregulloje sipas ctrader/UDHEZIME.md dhe nise prapë cBot-in. Trade-t e padërguara dërgohen atëherë.");
            Stop();
            return false;
        }

        private static string RedirectLink(string html)
        {
            var m = Regex.Match(html, "href=\"(https://script\\.google(usercontent)?\\.com/[^\"]+)\"", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value.Replace("&amp;", "&") : null;
        }

        private static string Snippet(string html)
        {
            var text = Regex.Replace(html, "<(script|style)[^>]*>.*?</\\1>", " ", RegexOptions.Singleline | RegexOptions.IgnoreCase);
            text = Regex.Replace(Regex.Replace(text, "<[^>]+>", " "), "\\s+", " ").Trim();
            return text.Length > 200 ? text.Substring(0, 200) + "..." : text;
        }

        private void Remember(Position p)
        {
            double dir = p.TradeType == TradeType.Buy ? 1 : -1;
            Levels lv;
            if (!_levels.TryGetValue(p.Id, out lv))
            {
                lv = new Levels();
                _levels[p.Id] = lv;
            }
            bool changed = false;
            if (!lv.Sl.HasValue && p.StopLoss.HasValue && (p.EntryPrice - p.StopLoss.Value) * dir > 0)
            {
                lv.Sl = p.StopLoss;
                changed = true;
            }
            if (!lv.Tp.HasValue && p.TakeProfit.HasValue && (p.TakeProfit.Value - p.EntryPrice) * dir > 0)
            {
                lv.Tp = p.TakeProfit;
                changed = true;
            }
            if (changed)
                SaveLevels();
        }

        private void LoadLevels()
        {
            var saved = LocalStorage.GetString("levels", Scope);
            if (string.IsNullOrEmpty(saved))
                return;
            foreach (var item in saved.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = item.Split(':');
                int id;
                if (parts.Length != 3 || !int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out id))
                    continue;
                _levels[id] = new Levels { Sl = ParseNullable(parts[1]), Tp = ParseNullable(parts[2]) };
            }
        }

        private void SaveLevels()
        {
            var sb = new StringBuilder();
            foreach (var kv in _levels.Where(kv => kv.Value.Sl.HasValue || kv.Value.Tp.HasValue))
                sb.Append(kv.Key.ToString(CultureInfo.InvariantCulture)).Append(':')
                  .Append(Format(kv.Value.Sl)).Append(':')
                  .Append(Format(kv.Value.Tp)).Append(';');
            LocalStorage.SetString("levels", sb.ToString(), Scope);
            LocalStorage.Flush(Scope);
        }

        private static string Format(double? v)
        {
            return v.HasValue ? v.Value.ToString("R", CultureInfo.InvariantCulture) : "";
        }

        private static double? ParseNullable(string s)
        {
            double v;
            return double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : (double?)null;
        }

        // EURJPY -> EUR/JPY, EURUSD.m -> EUR/USD; indekset (US30, NAS100) mbeten siç janë.
        private static string Pair(string symbol)
        {
            var s = (symbol ?? "").ToUpperInvariant();
            bool forex = s.Length >= 6 && s.Take(6).All(char.IsLetter) && (s.Length == 6 || !char.IsLetter(s[6]));
            return forex ? s.Substring(0, 3) + "/" + s.Substring(3, 3) : s;
        }

        private static string Quote(string s)
        {
            var sb = new StringBuilder("\"");
            foreach (var c in s ?? "")
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c < ' ') sb.AppendFormat(CultureInfo.InvariantCulture, "\\u{0:x4}", (int)c);
                else sb.Append(c);
            }
            return sb.Append('"').ToString();
        }
    }
}
