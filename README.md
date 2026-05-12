# LanguageTools

LanguageTools is a low-cost, long-lived local automation project built around plain shell tools, Python, Git, and scheduled background checks.

## Project status

- Last public sync attempt: 2026-05-12 06:48:46 PDT
- Current status: More automated than before
- Next planned update window: by 2026-05-26

## What changed

The script has become more automated because it now checks timed milestones, can create a scheduled marker file, writes non-confidential logs for review, verifies GitHub publishing readiness, and can refresh this README during the scheduled workflow.

## Why privacy matters

Putting PII, passwords, tokens, or other sensitive information on GitHub is not good because public repositories can expose private data permanently, make accidental leaks easy to copy, and create long-term security and privacy risks.

## Recent milestones

2026-04-11: Added scheduled publish automation.
2026-04-11: Added delayed marker-file creation logic.
2026-04-11: Added non-confidential logging for background runs.
2026-04-11: Added verifier script for reboot/login timing checks.
2026-04-11: Added automatic README refresh support.

## Publishing model

- Public-safe project files are staged from                   /opt/languagetools
- Confidential material stays out of the repo and belongs in /opt/languagetools-confidential
- Basic secret-pattern checks run before push

#AIS73 #VVtz
