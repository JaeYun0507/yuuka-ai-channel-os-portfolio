# 보안 현황 (npm audit)

- 확인일: 2026-10-23
- 확인 방법: `npm audit --json`을 직접 실행했어요. `npm audit fix` 결과가 반영된 `package-lock.json`(commit `8757f96`) 기준이에요.
- 사용자가 전달한 마지막 관측값(7개: moderate 2, high 5)과 같고, 악화는 없어요.
- 기계가 읽는 기준선은 [`scripts/auto-upload/security-baseline.json`](../scripts/auto-upload/security-baseline.json)에 있어요. 자동 업로드가 이 기준선과 현재 audit을 비교해요.

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

## 해결 방법에 대해

`npm audit`이 제시하는 자동 해결책은 `tailwindcss@4.3.3`(semver-major) 업그레이드 하나예요. 이것이 유일한 해결책이라고 확인한 것은 아니에요. 하위 패키지만 올리는 `overrides` 같은 다른 경로는 호환성을 평가하지 않았고, 평가 없이 적용하지도 않았어요.

## 상태와 방침

- **미해결**이에요. 무해하다고 판단하지 않았어요.
- 취약점은 DoS 계열이고 빌드 도구 체인에 있어요. 이 프로젝트에서 실제로 얼마나 노출되는지는 평가하지 않았어요.
- `npm audit fix --force`는 실행하지 않아요.
- 호환성이 확인되지 않은 `overrides`와 Tailwind 주요 버전 변경은 임의로 적용하지 않아요.
- 새 취약점, 새 advisory, 새 의존성 경로, 심각도 악화가 확인되면 자동 업로드가 차단돼요. 이때 보고하고 승인을 기다려요.
- 기존 7개가 줄어드는 변화는 차단하지 않아요. 기준선은 사람이 검토한 뒤에만 갱신해요.
