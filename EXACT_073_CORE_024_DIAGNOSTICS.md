# Chernogram 0.24 exact 0.7.3 diagnostics

Outcome: failure
Reference: d1cad8649d00259ab615e65ea196213713b2385f (0.7.3+14)
Time: 2026-07-29T15:51:26Z

```text
Traceback (most recent call last):
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_second_day_core_024.py", line 391, in <module>
    main()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_second_day_core_024.py", line 384, in main
    materialize_call_service()
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_second_day_core_024.py", line 282, in materialize_call_service
    text = replace_once(
           ^^^^^^^^^^^^^
  File "/home/runner/work/chernogram_new/chernogram_new/tooling/materialize_second_day_core_024.py", line 28, in replace_once
    raise RuntimeError(f"Patch anchor not found: {label}")
RuntimeError: Patch anchor not found: declined outcome
```
