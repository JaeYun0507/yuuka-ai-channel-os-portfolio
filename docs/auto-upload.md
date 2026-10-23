# 자동 업로드 (auto/claude)

전용 worktree에서 Claude Code를 실행하면, 응답이 끝날 때 변경을 검사하고 조건을 통과한 경우 `auto/claude` 브랜치에 자동으로 올려요.
**`main` 반영과 사이트 배포는 별도 작업이에요.** 이 자동화는 `main`을 바꾸지 않고, PR 생성이나 merge도 하지 않아요.

## 한눈에 보기

| 항목 | 내용 |
| --- | --- |
| 전용 폴더 | 메인 폴더 옆의 `yuuka-ai-channel-os-portfolio-auto` (git worktree) |
| 브랜치 | `auto/claude` (origin에 일반 push만 해요) |
| 실행 방식 | Claude Code `Stop` Hook → `powershell.exe -File scripts/auto-upload/auto-upload.ps1 hook` (동기) |
| 스위치·로그·잠금 | worktree의 git 디렉터리 안 `auto-upload/`에 저장돼요. 저장소 파일이 아니라서 Git에 올라가지 않아요 |

## 사용법

```powershell
# 1) 전용 worktree로 이동해서 Claude Code를 실행해요
Set-Location ..\yuuka-ai-channel-os-portfolio-auto
claude

# 상태 확인 / 켜기 / 끄기
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 status
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 enable
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 disable

# 수동 실행 (검사 + commit + push) / 검사만 (dry run)
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 run
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 check
```

- 메인 폴더(`yuuka-ai-channel-os-portfolio`)에서 실행한 Claude Code에는 이 Hook이 없어요.
- 이 폴더는 자동화 전용으로 쓰세요. 직접 수정한 내용과 Claude의 수정은 Git만으로 구분할 수 없어요. 첫 실행에 기존 변경이 있으면 사용자 변경으로 보고 중단해요.
- 스위치를 켜기 전까지는 아무것도 올라가지 않아요.

## 응답 종료(Stop)의 의미

`Stop`은 "Claude의 응답이 끝났다"는 신호예요. "기능이 완성됐다"는 뜻이 아니에요. 작업 도중의 중간 상태도 lint와 build를 통과하면 올라갈 수 있어요. 완성본만 올리고 싶으면 평소에는 `disable` 상태로 두고, 끝났을 때 `run`으로 수동 업로드하세요.

Hook은 실행 동안 Claude Code를 기다리게 해요. 정상일 때는 수십 초 안에 끝나고, 상한은 전체 780초(Hook timeout 840초)예요. Claude의 응답을 막거나 다시 시작시키지 않아요(`decision: block`을 쓰지 않고, 항상 종료 코드 0이에요). 실패해도 자동 재시도는 없고, 다음 응답 종료 때 다시 한 번 평가해요.

## 업로드 절차 (코드로 강제)

1. 활성화 여부, 경로(폴더 이름·형제 관계·linked worktree), origin, 브랜치, 실행 잠금 확인
2. merge/rebase/cherry-pick/revert/bisect 진행 여부와 충돌 확인
3. 변경 파일 목록과 이미 staged된 항목 확인. staged 항목이 있으면 섞지 않고 중단해요
4. 보호 파일(자동화·Hook 설정·`CLAUDE.md`·`.gitignore`) 변경 확인. 승인된 상태와 다르면 중단해요
5. 원격 `auto/claude` 관계 확인. 원격이 앞서거나 갈라졌으면 merge나 rebase 없이 중단해요
6. 금지 파일 이름 검사(추적 중인 파일 포함), 비밀정보 패턴 검사(변경 내용 전체 + 아직 안 올라간 모든 commit)
7. `npm run lint`, `npm run build`
8. 의존성 파일이 바뀌었거나 검증 이력이 없을 때만 `npm audit`을 실행하고 기준선과 비교해요
9. 검사 전후 스냅샷(HEAD, status, 대상 파일 해시) 비교. 달라졌으면 중단해요
10. 파일 하나씩 경로를 지정해 stage → staged diff 재검사 → commit (파일당 commit 1개, Conventional Commits)
11. `git push origin HEAD:refs/heads/auto/claude` (force 없음)
12. `git ls-remote`로 원격 SHA와 로컬 SHA 비교

commit은 성공했는데 push만 실패하면 commit은 로컬에 남고, 다음 실행이 "아직 안 올라간 commit"으로 인식해서 전체 범위를 다시 검사한 뒤 올려요.
어느 단계든 실패하면 이후 단계를 하지 않아요. 이 스크립트가 stage한 항목만 해제하고, 사용자 파일과 기존 staging은 건드리지 않아요.

## 비밀정보 보호와 한계

- 금지: `.env`, `.env.*`(`.env.example`만 허용), `*.pem`, `*.key`, 인증정보류 이름, `node_modules/`, `dist/`, `*.log`, `.claude/settings.local.json`
- 내용 검사: AWS·GitHub·Anthropic·OpenAI 형식·Google·Slack·Stripe 키, 개인키 블록, JWT, URL 속 인증정보, `key = "값"` 형태의 할당
- 의심 항목은 값을 출력하지 않고 규칙 이름·파일·줄 번호만 기록해요.
- **한계**: `gitleaks` 같은 검증된 도구가 아니라 정규식 패턴 검사예요. 패턴에 없는 형식, 인코딩·분할된 값, 문장 속에 풀어 쓴 비밀번호는 못 찾아요. "유출 가능성 없음"을 뜻하지 않아요. 검사 범위는 "이번에 바뀐 파일 + 아직 push되지 않은 commit"이라서, 이미 push된 과거 이력은 검사하지 않아요. 이력에 값이 있다면 고치지 않고 보고만 해야 해요. `gitleaks` 설치는 별도 승인 후에 검토해요.

## npm audit 기준선

- 기준선: [`scripts/auto-upload/security-baseline.json`](../scripts/auto-upload/security-baseline.json), 설명: [security-status.md](security-status.md)
- 개수만이 아니라 패키지, advisory, 의존성 경로, 설치 경로, 심각도를 비교해요. 새로 생기거나 나빠지면 차단해요.
- audit 조회 실패(오프라인, 시간 초과, 해석 불가)도 통과로 보지 않고 차단해요.
- 기존 7개는 **미해결**로 기록돼 있을 뿐, 해결되었거나 무해하다는 뜻이 아니에요.

## 자동화 자체의 변경 보호

`.claude/`, `scripts/auto-upload/`, `CLAUDE.md`, `.gitignore`는 보호 파일이에요. 사람이 검토하고 `approve -Yes`로 해시를 기록해야만 업로드가 진행돼요. 이 파일이 바뀐 채로는 어떤 변경도 올라가지 않아요.

```powershell
git diff -- .claude scripts/auto-upload CLAUDE.md .gitignore    # 검토
powershell.exe -NoProfile -File scripts\auto-upload\auto-upload.ps1 approve -Yes
```

이것은 실수와 자동 흐름을 막는 안전장치예요. 같은 컴퓨터에서 명령을 실행할 수 있는 주체를 막는 보안 경계는 아니에요. Claude에게 `approve`를 대신 실행하라고 하지 마세요.

## 테스트

```powershell
powershell.exe -NoProfile -File scripts\auto-upload\tests\run-tests.ps1
```

임시 폴더의 로컬 bare 저장소만 사용해요. GitHub에는 아무것도 올리지 않아요. 변경 없음, lint·build 실패, 비밀정보, 잘못된 경로·브랜치·origin, staged 변경, 동시 실행, 비활성화, push 실패 후 복구, 원격 충돌, 검사 중 변경, 보호 파일 변경 등을 검증해요.
