# Security Policy

SplitCrew handles expense records, receipt images, member names and payment-routing information. Security and privacy reports are treated seriously.

## Supported versions

Until v1.0, only the latest release and the current `main` branch receive security fixes.

## Reporting a vulnerability

Please do **not** disclose exploitable security issues in a public GitHub issue.

Use GitHub's private security-reporting/security-advisory mechanism for this repository when available. Include:

- affected version/commit;
- reproduction steps;
- impact;
- proof of concept where appropriate;
- suggested mitigation if known.

## Sensitive data rules

SplitCrew must never request or store:

- banking passwords;
- OTP codes;
- PINs;
- Internet-banking credentials;
- private signing keys in source control.

Payment adapters should store only the minimum routing information needed to construct a repayment request, such as account holder, bank identifier and destination account number.

## Repository secrets

Never commit `.env` files, keystores, signing certificates, tokens, production credentials, user databases or real receipt data containing unnecessary personal information.
