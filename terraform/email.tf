# ============================================================
# EMAIL INFRASTRUCTURE — SimpleLogin (Proton Mail)
# ============================================================
# This file defines DNS records required for SimpleLogin to
# handle email for czresume.com. SimpleLogin acts as an alias
# relay — mail sent to any @czresume.com alias is forwarded
# to your Proton Mail inbox. You can reply from aliases
# without revealing your real address.
#
# No mailbox is hosted on this domain. SimpleLogin handles:
#   - Receiving mail (MX records)
#   - Sending replies from aliases (SPF + DKIM)
#   - Anti-spoofing protection (DMARC)
# ============================================================


# ────────────────────────────────────────────────────────────
# DOMAIN VERIFICATION + SPF (combined TXT record)
# ────────────────────────────────────────────────────────────
# Route 53 allows only one TXT record set per name, so the
# SimpleLogin verification string and SPF record must live
# in the same resource as separate entries in the list.
#
# SPF (Sender Policy Framework) tells receiving mail servers
# which servers are authorized to send email on behalf of
# your domain. "include:simplelogin.co" authorizes
# SimpleLogin's servers. "~all" is a soft fail — mail from
# unauthorized servers gets flagged but not rejected outright.
# SimpleLogin recommends ~all rather than -all (hard fail)
# to avoid delivery issues during initial setup.
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "simplelogin_verification" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300

  records = [
    "sl-verification=gvnaxeodfrjzexvzaocbsphjazkqsf",
    "v=spf1 include:simplelogin.co ~all",
  ]
}


# ────────────────────────────────────────────────────────────
# MX RECORDS — Mail delivery
# ────────────────────────────────────────────────────────────
# MX (Mail eXchange) records tell the internet which servers
# handle incoming email for your domain. The priority number
# determines the order — lower = tried first.
#
# mx1 (priority 10) is the primary mail server.
# mx2 (priority 20) is the fallback if mx1 is unavailable.
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "simplelogin_mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300

  records = [
    "10 mx1.simplelogin.co.",
    "20 mx2.simplelogin.co.",
  ]
}


# ────────────────────────────────────────────────────────────
# DKIM RECORDS — Email signing
# ────────────────────────────────────────────────────────────
# DKIM (DomainKeys Identified Mail) lets SimpleLogin
# cryptographically sign outgoing emails so receiving servers
# can verify the message wasn't tampered with in transit.
#
# Each CNAME points to SimpleLogin's DKIM key servers. Three
# keys provide rotation capability — if one key is
# compromised, SimpleLogin can rotate to the next without
# breaking email delivery.
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "simplelogin_dkim1" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "dkim._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = ["dkim._domainkey.simplelogin.co."]
}

resource "aws_route53_record" "simplelogin_dkim2" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "dkim02._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = ["dkim02._domainkey.simplelogin.co."]
}

resource "aws_route53_record" "simplelogin_dkim3" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "dkim03._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = ["dkim03._domainkey.simplelogin.co."]
}


# ────────────────────────────────────────────────────────────
# DMARC RECORD — Anti-spoofing policy
# ────────────────────────────────────────────────────────────
# DMARC (Domain-based Message Authentication, Reporting &
# Conformance) tells receiving mail servers what to do when
# an email claiming to be from your domain fails SPF and
# DKIM checks.
#
# p=quarantine  — emails that fail authentication get sent to
#                 spam rather than rejected outright. This is
#                 safer than p=reject during initial setup.
# pct=100       — apply the policy to 100% of failing emails
# adkim=s       — strict DKIM alignment (the signing domain
#                 must exactly match the From domain)
# aspf=s        — strict SPF alignment (the envelope sender
#                 must exactly match the From domain)
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300

  records = [
    "v=DMARC1; p=quarantine; pct=100; adkim=s; aspf=s",
  ]
}
