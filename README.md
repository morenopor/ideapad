# ideapad

Hardware and software documentation for the Lenovo Ideapad development laptop lives in [docs/ideapad-hardware.md](docs/ideapad-hardware.md).

## Maintenance
To update and clean the laptop, run:

```bash
bash scripts/upkeep.sh           # update + clean + summary (log in ~/.local/state/upkeep/)
bash scripts/upkeep.sh --check   # summary only, changes nothing
```

Agents: this script is the maintenance procedure for this machine — run or extend it instead of issuing separate commands. Details in [docs/ideapad-hardware.md#maintenance](docs/ideapad-hardware.md#maintenance).
