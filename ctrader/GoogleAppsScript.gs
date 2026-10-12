/**
 * Raporti i Analizave – merr trade-t nga cTrader (cBot-i RaportiSync) dhe i shkruan te fleta "Raporti".
 *
 * Vendose këtë kod te Google Sheets: Extensions → Apps Script, pastaj
 * Deploy → New deployment → Web app (Execute as: Me, Who has access: Anyone).
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
    if (d.token !== TOKEN) return reply({ ok: false, error: 'token i gabuar' });
    return reply(addTrade(SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET), d));
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

// Hape URL-në e Web app në shfletues për të parë nëse lidhja punon.
function doGet() {
  return ContentService.createTextOutput('Lidhja me Raportin e Analizave punon.');
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

  const [y, m, day] = String(d.date).split('-').map(Number);
  const rr = d.rr === null || d.rr === undefined || d.rr === '' ? '' : Number(d.rr);
  sheet.getRange(row, 2, 1, 5).setValues([[new Date(y, m - 1, day), d.pair || '', d.setup || '', rr, d.status || '']]);
  if (d.note) sheet.getRange(row, 9).setValue(d.note);
  sheet.getRange(row, ID_COL).setValue(id);
  return { ok: true, row: row };
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
