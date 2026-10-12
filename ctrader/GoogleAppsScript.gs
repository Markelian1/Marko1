/**
 * Raporti i Analizave – merr trade-t nga cTrader (cBot-i RaportiSync) dhe i shkruan te fleta "Raporti".
 *
 * Vendose këtë kod te Google Sheets: Extensions → Apps Script, pastaj
 * Deploy → New deployment → Web app (Execute as: Me, Who has access: Anyone).
 * Pas çdo ndryshimi të kodit: Deploy → Manage deployments → ✏️ → Version: New version → Deploy.
 *
 * Funksioni rregulloRaportin() (zgjidhe lart dhe kliko Run) rikthen formulat e fshira
 * dhe ndërton grafikët Balance dhe Winrate direkt në Google Sheets.
 */

const TOKEN = 'NDRYSHO-KETE';   // i njëjti fjalëkalim si parametri "Token" te cBot-i
const SHEET = 'Raporti';
const FIRST = 12;               // rreshti i parë i trade-ve
const LAST = 511;               // rreshti i fundit
const ID_COL = 29;              // kolona AC (e fshehur) mban ID-në e pozicionit në cTrader

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const d = JSON.parse(e.postData.contents);
    if (d.token !== TOKEN) {
      console.warn('Token i gabuar për pozicionin ' + d.id);
      return reply({ ok: false, error: 'token i gabuar: TOKEN te skripti nuk është i njëjtë me Token te cBot-i' });
    }
    const result = addTrade(reportSheet(), d);
    console.log('Pozicioni ' + d.id + ': ' + JSON.stringify(result));
    return reply(result);
  } catch (err) {
    console.error(err);
    return reply({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// Hape URL-në e Web app në shfletues për të parë nëse lidhja punon.
function doGet() {
  return ContentService.createTextOutput('Lidhja me Raportin e Analizave punon.');
}

function reportSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) throw new Error('skripti nuk është i lidhur me raportin: hape nga raporti me Extensions → Apps Script');
  const sheet = ss.getSheetByName(SHEET);
  if (!sheet) throw new Error('nuk gjej fletën "' + SHEET + '"');
  return sheet;
}

function addTrade(sheet, d) {
  const count = LAST - FIRST + 1;
  const id = String(d.id);
  const ids = sheet.getRange(FIRST, ID_COL, count, 1).getValues();
  if (ids.some(r => String(r[0]) === id)) return { ok: true, duplicate: true };

  const cells = sheet.getRange(FIRST, 2, count, 5).getValues();   // B:F
  const i = cells.findIndex(r => r.every(v => v === ''));
  if (i < 0) return { ok: false, error: 'raporti është plot' };
  const row = FIRST + i;

  healFormulas(sheet);
  const [y, m, day] = String(d.date).split('-').map(Number);
  const rr = d.rr === null || d.rr === undefined || d.rr === '' ? '' : Number(d.rr);
  sheet.getRange(row, 2, 1, 5).setValues([[new Date(y, m - 1, day), d.pair || '', d.setup || '', rr, d.status || '']]);
  if (d.note) sheet.getRange(row, 9).setValue(d.note);
  sheet.getRange(row, ID_COL).setValue(id);
  return { ok: true, row: row };
}

// Rikthen formulat (Net, Balance dhe kolonat e fshehura Z:AB) në çdo rresht ku janë fshirë.
function healFormulas(sheet) {
  const count = LAST - FIRST + 1;
  const net = sheet.getRange(FIRST, 7, count, 1).getFormulas();
  const src = net.findIndex(r => r[0] !== '');
  if (src < 0) return;
  [[7, 2], [26, 3]].forEach(([col, width]) =>
    sheet.getRange(FIRST + src, col, 1, width).copyTo(
      sheet.getRange(FIRST, col, count, width), SpreadsheetApp.CopyPasteType.PASTE_FORMULA, false));
}

function rregulloRaportin() {
  const sheet = reportSheet();
  healFormulas(sheet);
  buildCharts(sheet);
  SpreadsheetApp.flush();
}

function buildCharts(sheet) {
  const BG = '#0B0B0B', GREY = '#9AA0A6', GRID = '#3C4043';
  sheet.getCharts().forEach(c => sheet.removeChart(c));

  const balance = (row, col, width, height, fontSize) => sheet.newChart().asAreaChart()
    .addRange(sheet.getRange(FIRST, 2, LAST - FIRST + 1, 1))   // Data (boshti X, i fshehur)
    .addRange(sheet.getRange(FIRST, 8, LAST - FIRST + 1, 1))   // Balance
    .setNumHeaders(0)
    .setPosition(row, col, 0, 0)
    .setOption('width', width)
    .setOption('height', height)
    .setOption('title', 'Balance')
    .setOption('titleTextStyle', { color: '#FFFFFF', fontSize: fontSize, bold: true })
    .setOption('backgroundColor', BG)
    .setOption('legend', { position: 'none' })
    .setOption('colors', ['#39E75F'])
    .setOption('areaOpacity', 0.35)
    .setOption('lineWidth', 2)
    .setOption('interpolateNulls', true)
    .setOption('treatLabelsAsText', true)
    .setOption('hAxis', { textPosition: 'none', gridlines: { color: 'transparent' } })
    .setOption('vAxis', { format: '0%', textStyle: { color: GREY, bold: true }, gridlines: { color: GRID }, baselineColor: GRID })
    .build();

  sheet.insertChart(balance(2, 11, 760, 480, 18));   // grafiku i madh te K2
  sheet.insertChart(balance(4, 6, 300, 165, 11));    // grafiku i vogël te F4
  sheet.insertChart(sheet.newChart().asPieChart()     // Winrate: WINS (jeshile) kundrejt LOSS (e kuqe)
    .addRange(sheet.getRange('B5:C6'))
    .setNumHeaders(0)
    .setPosition(5, 4, 0, 0)
    .setOption('width', 140)
    .setOption('height', 140)
    .setOption('pieHole', 0.55)
    .setOption('colors', ['#22C55E', '#EF4444'])
    .setOption('legend', { position: 'none' })
    .setOption('pieSliceText', 'none')
    .setOption('pieSliceBorderColor', BG)
    .setOption('backgroundColor', BG)
    .setOption('chartArea', { left: 5, top: 5, width: '90%', height: '90%' })
    .build());
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
