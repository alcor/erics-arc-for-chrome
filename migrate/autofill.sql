-- Merge Arc form autocomplete entries into Chrome Web Data. Run by arc-to-chrome.sh with Chrome closed.
ATTACH :arc AS arc;
BEGIN;
INSERT INTO autofill (name, value, value_lower, date_created, date_last_used, count)
SELECT name, value, value_lower, date_created, date_last_used, count FROM arc.autofill WHERE true
ON CONFLICT (name, value) DO UPDATE SET
  count = autofill.count + excluded.count,
  date_created = min(autofill.date_created, excluded.date_created),
  date_last_used = max(autofill.date_last_used, excluded.date_last_used);
COMMIT;
