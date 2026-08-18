# E.ON Atlassian ops repo

Odsud se pracuje s **Jira Data Center** (https://track.eon.cz) a **Confluence
Data Center** (https://dory.eon.cz). Hlavní projekt **AIC**.

**Načti skill `eon-atlassian`** (`.claude/skills/eon-atlassian/`) — drží
rozhodovací pravidlo mezi vrstvami, pasti DC, potvrzovací režim pro zápisy a
detailní recepty. Neimprovizuj z paměti, API Data Center se liší od Cloudu.

Dvě věci, které musí platit i bez načteného skillu:

- **Tokeny žijí jen v `.env`** (gitignored). Nikdy je nevypisuj do transkriptu,
  commitů ani logů. PAT vytváří uživatel sám ve webovém UI.
- **Zápis do Jiry/Confluence potvrď v chatu předem**, jedno volání = jeden
  souhlas. Po zápisu si objekt přečti zpět a cituj změněnou hodnotu.
