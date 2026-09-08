---
description: 이번 세션에서 한 일과 검증값을 journal.md에 붙인다. 날짜 단위로 묶고 위쪽은 고치지 않는다.
argument-hint: "[문서 디렉터리, 기본값 docs]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill
---

`project-doc-framework` 스킬을 호출해 **갱신** 절차를 1단계부터 끝까지 따른다.
대상 디렉터리는 `$1`이고, 비어 있으면 `docs`다.

`$1/journal.md`가 없으면 멈추고 `/doc-init`을 먼저 실행하라고 알린다.

절차와 보고 형식은 스킬의 갱신 절에 있다. 여기에는 따로 적지 않는다.
