// 포트폴리오 문구와 상태. 모든 수치는 2026-10-21에 직접 실행·확인한 값만 씁니다.
// 근거: ../../release/verification-report.md

export type Status = 'done' | 'wip' | 'plan' | 'unverified'

export const statusLabel: Record<Status, string> = {
  done: '동작·확인',
  wip: '진행·검토 중',
  plan: '설계·계획',
  unverified: '미확인',
}

// 공개 전 사용자가 직접 채울 값. 비어 있으면 화면에 표시하지 않습니다.
export const owner = {
  name: '',
  links: [] as { label: string; href: string }[],
}

export const lastUpdated = '2026-10-21'

export const nav = [
  { id: 'problem', label: 'Problem' },
  { id: 'solution', label: 'Solution' },
  { id: 'prototype', label: 'Prototype' },
  { id: 'qa', label: 'QA Case' },
  { id: 'role', label: 'My Role' },
  { id: 'tools', label: 'Tools' },
  { id: 'progress', label: 'Progress' },
  { id: 'learning', label: 'Learning' },
  { id: 'next', label: 'Next Steps' },
]

export const heroFacts = [
  { k: '기간', v: '2026.10 – 진행 중' },
  { k: '내 역할', v: '문제 정의 · 요구사항 · 검수 · 우선순위 판단' },
  { k: '현재 상태', v: '로컬 도구 동작, 사용자용 서비스는 설계 단계' },
]

export const problems = [
  { t: '얼굴 일관성', d: '생성할 때마다 미묘하게 다른 사람이 나옵니다. 무엇을 같은 얼굴의 기준으로 삼을지부터 정해야 했습니다.' },
  { t: '품질 편차', d: '손·피부·비율 결함이 섞여 나옵니다. 눈으로 대충 보면 놓치는 항목이 생깁니다.' },
  { t: '기록 분산', d: '어떤 프롬프트로 어떤 결과가 나왔는지가 여러 도구와 대화에 흩어집니다.' },
  { t: '원본 관리', d: '원본, 스크린샷, 복사본이 섞이면 무엇이 진짜 원본인지 알 수 없게 됩니다.' },
  { t: '공개 위험', d: '승인 전 이미지나 권리가 불분명한 자료가 실수로 공개될 수 있습니다.' },
  { t: '비용 통제', d: '재시도와 크레딧 사용을 기록하지 않으면 혼자서는 비용을 통제하기 어렵습니다.' },
]

export const solutions = [
  { t: '기준을 고정한다', d: '공식 얼굴 기준 이미지 1장을 파일 해시(SHA-256)로 고정하고, 원본은 수정하지 않고 복사본만 씁니다.' },
  { t: '모든 단계를 기록한다', d: '프롬프트 버전, 생성 기록, 자산 메타데이터, 항목별 QA 결과를 한곳에 남깁니다.' },
  { t: '사람이 승인한다', d: '비용이 드는 생성, 외부 공개, 삭제는 대상과 비용을 먼저 확인하고 사람이 승인한 뒤에만 실행합니다.' },
]

export const flow: { t: string; s: Status; d: string }[] = [
  { t: '기획', s: 'done', d: '기획 저장·검색·검토 상태·이력·버전 복구' },
  { t: '프롬프트', s: 'done', d: '버전 번호를 붙여 원문 보관' },
  { t: '이미지 생성', s: 'wip', d: '외부 생성 도구로 시험 1건' },
  { t: 'QA', s: 'wip', d: '항목별 기록, 최종 판정은 사람' },
  { t: '자산 기록', s: 'done', d: '파일 해시·메타데이터·백업' },
  { t: '개선', s: 'wip', d: '실패 원인 문서화 후 다음 시도' },
  { t: '게시 준비', s: 'plan', d: '게시 패키지·목록은 미구현' },
]

export const qaRows: { item: string; s: Status; result: string; note: string }[] = [
  { item: '얼굴 동일성', s: 'wip', result: 'REVIEW_REQUIRED', note: '머리 색·얼굴형·눈매는 유사, 미소 모양이 다름' },
  { item: '얼굴 해부 구조', s: 'done', result: 'PASS', note: '화면 크기에서 왜곡 없음' },
  { item: '피부 질감', s: 'wip', result: 'REVIEW_REQUIRED', note: '픽셀 단위 확인 불가' },
  { item: '손', s: 'wip', result: 'REVIEW_REQUIRED', note: '한 손은 자연스러움, 다른 손은 가려짐' },
  { item: '비율 · 장면 · 구도', s: 'done', result: 'PASS', note: '창가·라테·디저트·카디건 반영' },
  { item: '해상도', s: 'unverified', result: 'NOT_VERIFIED', note: '원본 파일 미확보' },
  { item: '게시 가능 여부', s: 'unverified', result: 'NOT_VERIFIED', note: '사람 판정 전, 게시하지 않음' },
]

export const roles = {
  me: ['목표 설정', '요구사항 정의', '도구 선택', 'AI 결과물 검토와 수정 지시', '기능 우선순위 판단', '공개 여부 결정'],
  ai: [
    'Claude Code — 코드 작성·수정, 테스트 작성',
    'ChatGPT · Codex — 독립 검토',
    'Google Stitch — 화면 시안·이미지 생성',
  ],
}

export const tools = [
  { g: 'AI 개발·협업', v: 'Claude Code, ChatGPT, Codex' },
  { g: '디자인·생성', v: 'Google Stitch, Higgsfield(생성 비용·품질 실험)' },
  { g: '웹 프로토타입', v: 'React, TypeScript, Vite, Tailwind CSS' },
  { g: '작업 관리', v: 'Git(파일 단위 커밋), 의사결정 기록, Node.js 테스트 실행' },
]

export const progress: { t: string; s: Status; evidence: string }[] = [
  { t: '콘텐츠 기획 관리 도구 (브라우저 로컬 저장, 단일 사용자)', s: 'done', evidence: '단위 테스트 40개 통과' },
  { t: '레퍼런스 이미지 수집 파이프라인 (승인 없는 생성 차단, 한도 도달 시 중단)', s: 'done', evidence: '자동 테스트 26개 통과' },
  { t: '운영 규칙 · 승인 게이트', s: 'done', evidence: '기능 모듈 8개, 의사결정 기록 10건' },
  { t: '생성 이미지 QA 기록', s: 'wip', evidence: '1건, 사람 최종 판정 대기' },
  { t: '사용자용 스튜디오 (서버 처리, 사용량·비용 서버 검증)', s: 'plan', evidence: '설계 문서만 있음' },
  { t: '게시 준비 목록 · 영상 제작 흐름', s: 'plan', evidence: '미구현' },
]

export const learnings = [
  {
    t: '캐릭터 음성 실험',
    tried: '내 PC에서 돌아가는 음성 합성 모델로 목소리를 시험했습니다.',
    result: '모델을 불러오는 순간 프로그램이 비정상 종료됐고, 합성은 한 번도 되지 않았습니다.',
    change: '로그와 시스템 이벤트를 대조해 메모리 부족을 가장 유력한 원인으로 기록했지만 확정하지 않았습니다. 재시도는 승인 후 1회로 제한했습니다.',
  },
  {
    t: '생성 이미지 보관',
    tried: '디자인 도구에서 만든 이미지를 원본 파일로 내려받으려 했습니다.',
    result: '결과가 캔버스에만 남고 원본 내보내기에 실패했습니다.',
    change: '스크린샷을 원본으로 대신하지 않고 ‘원본 보관 대기’ 상태를 따로 만들었습니다. 원본을 확보하기 전에는 다음 이미지를 만들지 않습니다.',
  },
  {
    t: '문서와 실제의 차이',
    tried: 'AI 도구별 역할을 문서로 정해 두고 작업했습니다.',
    result: '실제로 쓰는 도구와 문서의 역할 분담이 달라져 있었습니다.',
    change: '의사결정 기록으로 역할을 개정하고, 구현한 도구가 스스로 통과 판정하지 않도록 검토자를 분리했습니다.',
  },
]

export const nextSteps: { t: string; s: Status; d: string }[] = [
  { t: 'YUUKA AI CHANNEL OS', s: 'done', d: '운영 규칙, 기획 도구, 이미지 기록·QA 흐름' },
  { t: 'YUUKA Studio 내부 MVP', s: 'plan', d: '콘텐츠 1건을 기획부터 게시 준비까지 한 흐름으로 관리' },
  { t: '실제 사용 가능한 운영 도구', s: 'plan', d: '계정, 사용자별 데이터 분리, 서버 검증' },
  { t: '사용자 검증', s: 'plan', d: '소규모 크리에이터의 실제 피드백' },
]
