-- Merge Arc history (last 90 days; Chrome expires older visits anyway) into Chrome History.
-- Run by arc-to-chrome.sh with Chrome closed; :arc is a copy of Arc's History.
ATTACH :arc AS arc;
BEGIN;

CREATE TEMP TABLE cutoff AS SELECT (strftime('%s','now','-90 days') + 11644473600) * 1000000 AS t;

-- URLs Chrome already has: fold Arc counts in.
UPDATE urls SET
  visit_count = urls.visit_count + a.visit_count,
  typed_count = urls.typed_count + a.typed_count,
  last_visit_time = max(urls.last_visit_time, a.last_visit_time),
  title = CASE WHEN urls.title = '' THEN a.title ELSE urls.title END
FROM arc.urls a
WHERE a.url = urls.url AND a.last_visit_time > (SELECT t FROM cutoff);

-- New URLs.
INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden)
SELECT url, title, visit_count, typed_count, last_visit_time, hidden
FROM arc.urls
WHERE last_visit_time > (SELECT t FROM cutoff)
  AND url NOT IN (SELECT url FROM main.urls);

-- Visits, remapped to Chrome url ids. Referrer/opener links dropped (would point at Arc visit ids).
INSERT INTO visits (url, visit_time, from_visit, external_referrer_url, transition, segment_id,
  visit_duration, incremented_omnibox_typed_score, opener_visit, originator_cache_guid,
  originator_visit_id, originator_from_visit, originator_opener_visit, is_known_to_sync,
  consider_for_ntp_most_visited, visited_link_id, app_id)
SELECT c.id, v.visit_time, 0, v.external_referrer_url, v.transition, 0,
  v.visit_duration, v.incremented_omnibox_typed_score, 0, '',
  0, 0, 0, 0,
  v.consider_for_ntp_most_visited, 0, v.app_id
FROM arc.visits v
JOIN arc.urls a ON a.id = v.url
JOIN main.urls c ON c.url = a.url
WHERE v.visit_time > (SELECT t FROM cutoff);

COMMIT;
