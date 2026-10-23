# 보안 현황 (npm audit)

- 확인일: 2026-10-23
- 확인 방법: `npm audit --json` 직접 실행 (작업 트리 기준, `package-lock.json`에는 아직 commit되지 않은 `npm audit fix` 변경이 있음)
- 사용자가 전달한 마지막 관측값(7개: moderate 2, high 5)과 동일하며 악화는 없음

## 요약

| 심각도 | 개수 |
| --- | --- |
| critical | 0 |
| high | 5 |
| moderate | 2 |
| 합계 | 7 |

## 의존성 경로

직접 의존성은 `tailwindcss` 하나이고, 나머지 6개는 그 하위(전이) 의존성이에요.

| 패키지 | 심각도 | 원인 |
| --- | --- | --- |
| tailwindcss (직접) | high | 아래 하위 패키지 경유 |
| chokidar | high | braces 경유 |
| fast-glob | high | micromatch 경유 |
| micromatch | high | braces 경유 |
| braces | high | GHSA 1240992: 깊게 중첩된 패턴에 의한 stack-exhaustion DoS |
| postcss-nested | moderate | postcss-selector-parser 경유 |
| postcss-selector-parser | moderate | GHSA 1241232: 평면 selector 파싱의 quadratic complexity로 인한 CPU 소진 |

## 자동 수정 가능 여부

`npm audit`이 제시하는 해결책은 `tailwindcss@4.3.3`(semver-major)로의 업그레이드뿐이에요. Tailwind 3 → 4는 설정 방식(`tailwind.config.js`, PostCSS 플러그인)이 바뀌는 마이그레이션이라 자동 적용하지 않았어요.

## 상태와 방침

- **미해결**입니다. 무해하다고 판단하지 않았어요.
- 해당 취약점은 DoS 계열이라, 빌드 시점 도구 체인(Tailwind 컨텐츠 스캔)에서 신뢰할 수 없는 입력을 처리할 때 문제가 될 수 있어요. 이 프로젝트의 실제 노출 정도는 별도로 평가하지 않았어요.
- `npm audit fix --force`는 실행하지 않아요.
- 호환성이 확인되지 않은 `overrides`는 적용하지 않아요.
- 해결하려면 Tailwind 4 마이그레이션을 별도 작업으로 계획하고 승인받은 뒤 진행해요.
- 새 취약점이 생기거나 위 표보다 악화되면 보고하고 승인을 기다려요.
