# APP live-room entry and fullscreen clicks

User-confirmed scope: distinct yyuid across Android, iOS, iPad, Android tablet and HarmonyOS on 2026-11-12. Reuses the APP product list in the archived World Cup user-click SQL. The originally requested Desktop/SQL directory is unavailable on this machine.

Entry: pageview/liveroom. Click: click/verticallive/fullscreen (vertical live-room fullscreen button per supplied screenshot); actual screen rotation is not established. Both dt and server stime must be on the target date. Excludes null, empty, 0 and -1 UID; no separate authenticated-session validation.

main.sql aggregates per-user flags. independent.sql independently counts distinct UIDs directly from the source. sample.sql checks five users with repeated events. Cross-product UVs must not be summed.

Entry 2,886,207; click 1,570,641; intersection 1,560,939 without temporal ordering; click without same-day entry 9,702. No target click events observed on iPad, and neither target event observed on Android tablet; absent instrumentation does not establish zero actual behavior.

Only reusable SQL and aggregate validation evidence are archived. No credentials or user-level exports. See validation.md and README.md.

Follow-up: an unrestricted-ety scan (RID 1241320559786855936) found the two target IDs only under custom_event, with unchanged source counts. Related IDs usr/click/fullscreenbutton and click/minilive/fullscreen also exist; their equivalence to the requested action is unverified. Do not sum them or describe 1,570,641 as all landscape/fullscreen operations. See validation.md and the two diagnostic SQL files.

## Cross-check against viewing users
Online lineage and distinct-UID reconciliation are now complete. Entry UV 2,886,207 vs behavior/server-session partition UV 2,908,223: 0.7570% difference. Restricting viewing intervals to overlap 2026-11-12 gives 2,893,808 on both tables: 0.2627% difference. Both pass the user-requested 3% aggregate threshold. No minimum viewing duration or extra black-user exclusion; this acceptance must not be extended to positive-duration viewers. The actual traced live-watch upstream uses system_event; pageview/liveroom was discovered by querying event IDs, not obtained from the event dictionary, and is not proven to feed the viewing tables. See watch-validation.md and the reconciliation/independent SQL files. Individual room/time event matching was not performed.
