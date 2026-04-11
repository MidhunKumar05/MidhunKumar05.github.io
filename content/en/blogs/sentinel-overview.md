---
title: "Building Sentinel: Compliance Software for Australian Hospitality"
date: 2026-04-11T10:30:00+11:00
draft: false
tags: ["Django", "Next.js", "PostgreSQL", "AWS S3", "TypeScript", "SaaS", "Docker", "Kubernetes", "RESTful"]
categories: ["Projects"]
description: "How working at a Melbourne pub led me to build Sentinel — The OS for Hospitality"
---

I currently work as a Bartender in the North Eastern Suburbs of Melbourne at a local Pub Chain. One of those venues is called Dorset Gardens Hotel. A medium to large sized venue under the management of a organisation named JMS Hospitality.

## The Problem
As per Australian laws, all employees must have certificates in order to be in certain departments. If serving alcohol, you must have a Victorian RSA. In gaming? RSG and an RSA. And not to forget about the certifications the venue itself must hold such as Anti-Money Laundering and Counter Terrorism Financing documents.

## The Client and The Constraints : JMS Hospitality
1. Approximately 7 venues across victoria, 450 employees. Thinking in O(n) worst case, O(number of employees x number of certs) for space. All PDF format or other related formats. 

2. Average age of user is approximately 50 (not very tech savvy): thus user interface is very similar to excel since that's their current solution.

3. Must be simple and modular, since each certificate is treated different from each other, and as new laws pass, more certificates are added and removed.

4. Security is key. Security as no 1, is non negotiable, encryption of files, and permission management as well as vps best practices and availability.

## The Solution: What Sentinel Does

Disclaimer: Claude was used to summarise my excessive tangent.

Sentinel is a multi-tenant SaaS platform that centralises compliance and certificate management for Australian hospitality venues. The core idea is simple: give an operator a single place to see the compliance status of every employee across every venue they run, with automated alerts before certificates expire and structured workflows for the regulatory reporting they are already required to do.

The platform is built around a three-level hierarchy: Organisation → Venue → Employee. An organisation (say, a hospitality group) can manage multiple venues, and each venue manages its own staff. Role based permission.

**Certificate Management** covers the certificates that hospitality workers are legally required to hold: Responsible Service of Alcohol (RSA), Food Safety, First Aid, and gaming-specific certifications. Sentinel tracks issue dates, expiry dates, and sends alerts before certificates lapse.

**AML/CTF Compliance** is the more specialised layer. Gaming-licensed venues in Victoria operate under the Anti-Money Laundering and Counter-Terrorism Financing Act and are required to maintain documented compliance programs. 

**Multi-Venue Dashboard** shows venue health cards across an organisation's entire portfolio. Compliance scores, certificate expiry counts, and outstanding submissions are visible in one view. 

## The Stack

I built Sentinel with tools I trust for production use:

**Frontend:** Next.js, TypeScript, Tailwind CSS 4, Zustand for state management, React Query for server state, custom AXIOS api called mimir (based on norse god), all visual computation such as tables is mainly done on the client machine to keep serverload minimal. Caching is also implemented.

**Backend:** Django Rest Framework backend, CRUD heavy with rate limiting on the backend as well as the Traefik (possibly redundant). Django was chosen for the "batteries included", thus rapid development. User Sessions in Redis, Postgres for Relational, minIO for S3. Restrictive use of SQL due to Django ORM (I love the ORM). Fake data generated through regular expressions and the Faker Library (for the demo site), resets at 12 am AEST with Cron job.

**Data:** PostgreSQL as the primary database, Redis for caching and session management.

**Storage:** AWS S3 compatible MinIO (done for scale ready).

**Infrastructure:** Docker for containerisation, deployed on VPS. Switching over to k3s, argoCD and Helm stack. (see my homelab blog).

**Telemetry and Analytics:** Google Search Console, Bing Webmaster, HyperDX, Umami.

multiple deployments are running: `demo.korvant.au` for prospective clients.

## Why I Built It This Way

The honest answer is that I built Sentinel because I was the target user. Working at a gaming-licensed venue made the compliance burden concrete, not abstract. My RSA has an expiry date. When a staff member's certificate lapses, someone has to notice, otherwise both the employee and the venue cop a fine, the venue being near 20 grand.

Software that solves a real problem for a real client is a better forcing function than any university assignment. Sentinel is in production, it is generating revenue, and the requirements I am building against come from an actual hospitality operator, not a product spec I wrote for myself.

## The Next Phase
Incorporating a Knowledge based assistant AI (SLM, LLMs are overrated) that tells exactly how to price, hire and grow. 

## The Hint
A hint on whats to come: You could either hire someone super smart how supposedly knows a lot but is expensive, or someone whose not as experienced by with the access with all the right tools and at a darn good value.
