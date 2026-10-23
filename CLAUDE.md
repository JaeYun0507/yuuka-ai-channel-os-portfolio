# yuuka-ai-channel-os-portfolio 작업 지침

- 원격: https://github.com/JaeYun0507/yuuka-ai-channel-os-portfolio (**공개 저장소** — 비밀정보 유출 방지가 최우선)
- 로컬: `C:\Users\bjy03\Projects\yuuka-ai-channel-os-portfolio`
- 자동 업로드 전용 worktree: 메인 폴더 옆 `yuuka-ai-channel-os-portfolio-auto` (브랜치 `auto/claude`)
- 이 문서는 작업 지침이며 GitHub 인증이나 실행 권한을 부여하지 않습니다.

## 시작 전 확인
- 실제 프로젝트 경로, Git 저장소 루트, 현재 브랜치, origin URL을 확인합니다.
- 위 대상과 다르면 수정·push 없이 중단합니다.
- `git status`와 `git diff`로 기존 사용자 변경과 이번 작업을 구분합니다. 기존 변경을 덮어쓰거나 임의로 commit에 포함하지 않습니다.
- 충돌이나 출처가 불명확한 변경이 있으면 질문합니다.

## 코드 수정 작업 종료 절차
(메인 worktree에서의 수동 절차입니다. 전용 worktree는 아래 "자동 업로드"를 따릅니다.)

변경 검토 → 비밀정보 검사 → `npm run lint` → `npm run build`
→ 이번 작업 관련 파일만 명시적으로 stage → staged diff 재검토
→ commit → push → 원격 반영 확인(로컬 SHA와 `origin/<branch>` SHA 비교)

- 위 절차를 모두 통과한 코드 수정 작업의 commit·push는 허용됩니다.
- 현재 브랜치로 push합니다. `main` 직접 push가 제한되면 우회하지 말고 브랜치와 PR 방식을 제안합니다.
- 일반 질문, 읽기 전용 조사에는 commit·push하지 않습니다.
- 변경이 없으면 빈 commit을 만들지 않습니다.
- commit은 파일마다 개별로 만들고 Conventional Commits(`feat:`, `fix:`, `docs:`, `chore:` 등)를 따릅니다.

## 비밀정보와 제외 파일
- `.env`, `.env.*`, `node_modules/`, `dist/`는 commit하지 않습니다. 값이 없는 템플릿 `.env.example`만 허용합니다.
- API 키, 토큰, 암호, 개인키, 인증정보 파일을 commit하지 않습니다.
- `.gitignore`만 믿지 않습니다. 추적 중인 파일과 staged diff도 검사합니다.
- 비밀정보를 발견하면 값을 출력하지 말고 파일 위치와 필요한 조치만 알립니다.
- 이미 Git 이력에 있으면 이력을 자동으로 수정하지 말고 보고합니다.
- `git add .`, `git add -A` 대신 이번 작업 파일 경로를 지정합니다.

## 중단 조건
lint/build 실패, 비밀정보 발견, Git 충돌, 인증 실패, push 거절, 원격 저장소 불일치 시 commit·push를 중단하고 보고합니다.

- `git push --force`, `git reset --hard`, `git clean`, `--no-verify` 같은 검증 우회 옵션을 쓰지 않습니다.
- 원격 변경 때문에 push가 거절되면 임의로 merge하거나 rebase하지 않습니다.
- 종료 Hook이나 파일 감시로 자동 push하는 설정은 아래 "자동 업로드"에 정의된 Stop Hook 하나만 허용합니다. 그 밖의 자동 push 설정(다른 Hook, 파일 감시, 예약 작업)은 설치하지 않습니다.

## 자동 업로드 (전용 worktree 한정)
- 전용 worktree에서 실행한 Claude Code에서만 적용됩니다. Stop Hook(`.claude/settings.json`)이 `scripts/auto-upload/auto-upload.ps1`을 실행해 검사하고, 통과하면 `auto/claude`에 commit·push합니다. 상세는 [docs/auto-upload.md](docs/auto-upload.md)입니다.
- 이 브랜치에서는 Hook이 업로드를 담당하므로 직접 `git commit`·`git push`를 하지 않습니다. 수동 업로드는 사용자가 요청할 때 `auto-upload.ps1 run`으로만 합니다.
- 허용 범위는 `auto/claude`로의 일반 push뿐입니다. `main` 직접 push, 자동 merge, PR 생성·merge, force push는 하지 않습니다. `main` 반영과 사이트 배포는 별도 작업입니다.
- `.claude/`, `scripts/auto-upload/`, `CLAUDE.md`, `.gitignore`는 보호 파일입니다. 사용자가 요청하지 않으면 수정하지 않고, 수정했다면 검토를 요청합니다.
- `auto-upload.ps1`의 `approve`, `baseline`, `enable`, `disable`은 사용자만 실행합니다. 대신 실행하거나 검사를 우회하지 않습니다.
- Hook이 실패하면 원인을 보고합니다. `-ExecutionPolicy` 변경, 검사 비활성화, 설정 수정으로 우회하지 않습니다.
- 응답 종료는 기능 완성을 뜻하지 않습니다. 중간 상태도 검사를 통과하면 올라갈 수 있습니다.

## 인증과 권한
- 기존 Git/GitHub CLI 인증 상태를 확인합니다. 로그인이 필요하면 절차만 안내하고, 토큰이나 암호를 채팅에 입력하라고 요구하지 않습니다.
- Claude Code 권한 확인을 우회하거나 전체 권한 허용 설정을 적용하지 않습니다.

## 보안 경고 (npm audit)
- 현황은 [docs/security-status.md](docs/security-status.md)에 기록합니다.
- `npm audit fix --force`를 실행하지 않습니다.
- Tailwind 4 마이그레이션이나 호환성이 불명확한 `overrides`를 임의로 적용하지 않습니다.
- 남은 취약점을 해결됐거나 무해하다고 표현하지 않습니다.
- 기록된 항목보다 새 취약점이 생기거나 악화되면 보고하고 승인을 기다립니다.
