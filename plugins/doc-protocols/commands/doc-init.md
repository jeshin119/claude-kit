---
description: 프로젝트 문서 골격을 세운다. 규모를 판정하고 M/L 프로파일에 맞는 파일만 만든다. CLAUDE.md 가 없으면 문서 규칙 네 줄과 함께 만든다.
argument-hint: "[문서 디렉터리, 기본값 docs]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill, AskUserQuestion
---

`project-doc-framework` 스킬을 불러 **세우기** 절차를 1단계부터 끝까지 따른다.
대상 디렉터리는 `$1` 이고, 비어 있으면 `docs` 다.

절차와 보고 형식은 스킬의 세우기 절에 있다. 여기에는 따로 적지 않는다.
