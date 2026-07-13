<!--
  WIKI EDITOR NOTE
  This file is the wiki-ready source for the IAM Roles Anywhere subsection of the
  Amazon Route53 entry on the `dnsapi` wiki page
  (https://github.com/acmesh-official/acme.sh/wiki/dnsapi).

  To publish: paste the content BELOW this comment as a subsection immediately after
  the existing "Use Amazon Route53 domain API" section, keeping the existing
  `dns_aws` anchor untouched. The `<a name="dns_aws_rolesanywhere"/>` anchor below lets
  other pages deep-link to it.
-->

<a name="dns_aws_rolesanywhere"/>

## Use Amazon Route53 with IAM Roles Anywhere (X.509 certificate auth)

`dns_aws` can authenticate to AWS using an **X.509 client certificate** through
[AWS IAM Roles Anywhere](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/introduction.html)
instead of a long-lived `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` pair.

### Why use this instead of long-lived access keys

A static access key is a **bearer secret with no built-in expiry**. If it leaks — from
a backup, a config-management repo, a compromised host, an error log — it stays valid
until a human notices and revokes it, and it grants its full IAM permissions to whoever
holds it. On a machine that runs acme.sh unattended, that key typically sits in
`account.conf` for months or years.

Access keys also **require an IAM user**. As AWS puts it, "access keys are long-term
credentials for an IAM user or the AWS account root user" — an IAM role cannot hold
permanent access keys, it only vends temporary ones. So the classic setup means
creating a dedicated IAM user for acme.sh, attaching a policy to it, and managing that
user's key lifecycle (rotation, the two-key limit, offboarding) forever. That standing
user is itself an object to secure and audit.

IAM Roles Anywhere removes that: the certificate assumes an IAM **role** directly, so
**no IAM user exists** for acme.sh at all — there is no per-user key to create, rotate,
or leak. It replaces the whole arrangement with a certificate-based exchange:

- **No standing secret, and no IAM user, in AWS.** The host proves its identity with a
  client certificate signed by a CA you registered as a *trust anchor*, and assumes a
  role. AWS returns **temporary** credentials (default 1 hour here) that acme.sh holds
  only in memory and never writes to disk.
- **Short-lived and rotatable.** You control certificate lifetime and can rotate on a
  schedule; a leaked cert stops working when it expires.
- **Revocable at the source.** Disable the trust anchor or profile and every host using
  it loses access immediately — no key hunting.
- **Natural fit.** acme.sh already manages certificates; giving it one more cert to
  authenticate with keeps the whole trust story in PKI rather than in shared secrets.

### How it works

```
client cert + key ──sign CreateSession──► rolesanywhere.<region>.amazonaws.com
                                                   │
                                          temporary AWS credentials
                                                   │
                                                   ▼
                                    Route53 API (existing SigV4 path)
```

acme.sh signs a `CreateSession` request with the certificate's private key
(`AWS4-X509-RSA-SHA256` or `AWS4-X509-ECDSA-SHA256`, chosen automatically from the key
type), sends the certificate in the `X-Amz-X509` header, and exchanges it for temporary
`accessKeyId` / `secretAccessKey` / `sessionToken`. Everything after that is the normal
Route53 flow.

### Prerequisites (one-time AWS setup)

You need three things in AWS, then three ARNs from them:

1. A **trust anchor** — a CA whose certificates AWS will trust.
2. An **IAM role** the certificate is allowed to assume (with Route53 permissions).
3. A **profile** linking the trust anchor and the role.

See [Getting started with IAM Roles Anywhere](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/getting-started.html).

### Getting the client certificate

> **Important:** the Roles Anywhere client certificate **cannot** be issued by acme.sh's
> own ACME flow. That would be circular — acme.sh needs these credentials to solve the
> DNS challenge in the first place. The cert must come from your **trust-anchor CA**.

Pick one of the two CA models below.

#### Option A — AWS Private CA (ACM PCA), the managed path

Use this if you want AWS to run the CA and you're comfortable with its
[monthly cost](https://aws.amazon.com/private-ca/pricing/).

1. Create a Private CA in ACM PCA and register it as the trust anchor.
2. Issue an end-entity certificate + key for this host. With the ACM PCA CLI you can
   generate a key + CSR locally and have PCA sign it, keeping the private key on the
   host (never upload it):
   ```sh
   openssl req -new -newkey rsa:2048 -nodes \
     -keyout ~/.aws/rolesanywhere/private-key.pem \
     -out /tmp/host.csr -subj "/CN=$(hostname -f)"

   aws acm-pca issue-certificate \
     --certificate-authority-arn "$PCA_ARN" \
     --csr fileb:///tmp/host.csr \
     --signing-algorithm SHA256WITHRSA \
     --validity Value=7,Type=DAYS

   aws acm-pca get-certificate \
     --certificate-authority-arn "$PCA_ARN" \
     --certificate-arn "$CERT_ARN" \
     --output text --query Certificate \
     > ~/.aws/rolesanywhere/certificate.pem
   ```

#### Option B — Self-managed CA (openssl / step-ca), the sovereign path

Use this if you already run a PKI, or want full control and no AWS PCA cost. Register
your CA's **root (or intermediate) certificate** as the trust anchor with an external
certificate bundle.

Minimal openssl example (a real deployment should protect the CA key properly):
```sh
# One-time: create the CA (this cert becomes the trust anchor in AWS)
openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
  -keyout ca.key -out ca.crt -subj "/CN=acme-sh Roles Anywhere CA"

# Per host: key + CSR, signed by the CA
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ~/.aws/rolesanywhere/private-key.pem \
  -out host.csr -subj "/CN=$(hostname -f)"
openssl x509 -req -in host.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -days 7 -out ~/.aws/rolesanywhere/certificate.pem
```

[step-ca](https://smallstep.com/docs/step-ca/) is a good self-hosted option for
automating short-lived certificate issuance.

EC keys (P-256) work too — acme.sh selects `AWS4-X509-ECDSA-SHA256` automatically.

### Where to store the certificate and key (opinionated default)

acme.sh looks for the cert and key at, by default:

```
~/.aws/rolesanywhere/certificate.pem
~/.aws/rolesanywhere/private-key.pem
```

This location is deliberate: it lives under the **standard AWS config directory**
(`~/.aws/`), so the *same* files work unchanged with the official
[`aws_signing_helper`](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html)
and the AWS CLI's `credential_process` — acme.sh does not invent a private convention.
Keeping them in a dedicated `rolesanywhere/` subdirectory separates them from
`~/.aws/credentials` and lets you secure and back up the whole directory as one unit.

Lock the permissions down — this key is a credential:
```sh
mkdir -p ~/.aws/rolesanywhere
chmod 700 ~/.aws/rolesanywhere
chmod 600 ~/.aws/rolesanywhere/private-key.pem ~/.aws/rolesanywhere/certificate.pem
```

Override the paths with `AWS_RA_CERT` / `AWS_RA_KEY` if you store them elsewhere (for
example, a TPM- or PKCS#11-backed key managed by `aws_signing_helper` directly).

### Configuration

```sh
export AWS_RA_TRUST_ANCHOR_ARN="arn:aws:rolesanywhere:eu-central-1:123456789012:trust-anchor/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export AWS_RA_PROFILE_ARN="arn:aws:rolesanywhere:eu-central-1:123456789012:profile/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export AWS_RA_ROLE_ARN="arn:aws:iam::123456789012:role/acme-route53"

# Optional — defaults shown
# export AWS_RA_CERT="$HOME/.aws/rolesanywhere/certificate.pem"
# export AWS_RA_KEY="$HOME/.aws/rolesanywhere/private-key.pem"
# export AWS_RA_REGION="eu-central-1"     # else parsed from the trust anchor ARN
# export AWS_RA_DURATION="3600"           # session length in seconds (900-43200)

acme.sh --issue --dns dns_aws -d example.com -d '*.example.com'
```

When the three `AWS_RA_*` ARNs are set, Roles Anywhere is used **in preference to**
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` and to ECS/EC2 instance roles, because
configuring it is an explicit choice. The three ARNs are saved to `account.conf` for
reuse; the certificate/key **paths** are saved, but the temporary credentials and the
private key itself are never written there.

If the ARNs are set but the certificate or key file is missing, acme.sh reports an
error and stops rather than silently falling back to another auth method — a
half-configured Roles Anywhere setup is almost always a mistake worth surfacing.

### Rotating the client certificate

Roles Anywhere is most valuable with **short-lived** certificates. Issue them for days,
not years, and rotate before expiry. Because acme.sh reads the cert fresh on every run,
rotation just means overwriting the two files in place.

Example daily rotation with a self-managed CA (adapt for ACM PCA), via cron:
```sh
# /etc/cron.daily/rotate-ra-cert  (chmod +x)
#!/bin/sh
set -eu
DIR="$HOME/.aws/rolesanywhere"
openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$DIR/private-key.pem.new" \
  -out /tmp/host.csr -subj "/CN=$(hostname -f)"
openssl x509 -req -in /tmp/host.csr \
  -CA /etc/pki/ra-ca.crt -CAkey /etc/pki/ra-ca.key -CAcreateserial \
  -days 7 -out "$DIR/certificate.pem.new"
chmod 600 "$DIR/private-key.pem.new" "$DIR/certificate.pem.new"
mv "$DIR/private-key.pem.new" "$DIR/private-key.pem"
mv "$DIR/certificate.pem.new" "$DIR/certificate.pem"
rm -f /tmp/host.csr
```
A systemd timer works equally well. Keep the rotation cadence comfortably shorter than
the certificate validity so a missed run doesn't lock you out.

### Troubleshooting

Run with `--debug 2` and check:

- `AccessDeniedException` from CreateSession → the role trust policy, the profile, or
  the trust anchor doesn't accept this certificate. Verify the cert chains to the
  registered trust anchor and the role trusts the `rolesanywhere` service principal.
- `Unsupported Roles Anywhere key type` → the private key is neither RSA nor EC, or is
  passphrase-protected. Use an unencrypted RSA or EC (P-256) key (v1 signs with SHA-256).
- Clock skew → CreateSession is time-sensitive; keep the host's clock in sync (NTP).

### Limitations (current implementation)

- Signs with SHA-256 (covers RSA and NIST P-256 EC certificates). P-384/P-521 and ML-DSA
  are not yet handled.
- Passphrase-protected private keys and intermediate-chain presentation
  (`X-Amz-X509-Chain`) are not yet supported. For PKCS#11/TPM-backed keys, point
  `AWS_RA_*` at credentials produced by the official `aws_signing_helper` instead.
