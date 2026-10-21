import { useState, type ReactNode } from 'react'
import {
  flow,
  heroFacts,
  lastUpdated,
  learnings,
  nav,
  nextSteps,
  owner,
  problems,
  progress,
  qaRows,
  roles,
  solutions,
  statusLabel,
  tools,
  type Status,
} from './content'

const badgeClass: Record<Status, string> = {
  done: 'bg-emerald-50 text-emerald-800 border-emerald-200',
  wip: 'bg-amber-50 text-amber-800 border-amber-200',
  plan: 'bg-slate-100 text-slate-700 border-slate-200',
  unverified: 'bg-rose-50 text-rose-800 border-rose-200',
}

function Badge({ s, children }: { s: Status; children?: ReactNode }) {
  return (
    <span className={`inline-block whitespace-nowrap rounded-full border px-2 py-0.5 text-xs font-semibold ${badgeClass[s]}`}>
      {children ?? statusLabel[s]}
    </span>
  )
}

function Section({ id, kicker, title, children }: { id: string; kicker: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="border-t border-ivoryBorder py-14 sm:py-20">
      <div className="mx-auto max-w-5xl px-5 sm:px-8">
        <p className="text-xs font-bold uppercase tracking-[0.18em] text-roseTone-600">{kicker}</p>
        <h2 id={`${id}-title`} className="mt-2 text-2xl font-bold leading-snug sm:text-3xl">
          {title}
        </h2>
        <div className="mt-8">{children}</div>
      </div>
    </section>
  )
}

function Header() {
  const [open, setOpen] = useState(false)
  return (
    <header className="sticky top-0 z-40 border-b border-ivoryBorder bg-cream/95 backdrop-blur">
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-5 sm:px-8">
        <a href="#top" className="font-bold tracking-tight">
          YUUKA <span className="text-roseTone-600">AI CHANNEL OS</span>
        </a>
        <button
          type="button"
          className="rounded-full border border-ivoryBorder px-3 py-1.5 text-sm lg:hidden"
          aria-expanded={open}
          aria-controls="site-nav"
          onClick={() => setOpen((v) => !v)}
        >
          {open ? '닫기' : '메뉴'}
        </button>
        <nav id="site-nav" aria-label="섹션" className="hidden lg:block">
          <ul className="flex gap-5 text-sm text-warmGray">
            {nav.map((n) => (
              <li key={n.id}>
                <a className="hover:text-roseTone-600" href={`#${n.id}`}>
                  {n.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>
      {open && (
        <nav aria-label="섹션 (모바일)" className="border-t border-ivoryBorder lg:hidden">
          <ul className="mx-auto grid max-w-5xl grid-cols-2 gap-1 px-5 py-3 text-sm sm:grid-cols-3">
            {nav.map((n) => (
              <li key={n.id}>
                <a className="block rounded-lg px-3 py-2 hover:bg-roseTone-50" href={`#${n.id}`} onClick={() => setOpen(false)}>
                  {n.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      )}
    </header>
  )
}

function App() {
  return (
    <div id="top" className="min-h-screen bg-cream text-berry antialiased">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-50 focus:rounded-full focus:bg-white focus:px-4 focus:py-2 focus:text-sm"
      >
        본문으로 건너뛰기
      </a>
      <Header />

      <main id="main" tabIndex={-1}>
        {/* 1. Hero */}
        <section aria-labelledby="hero-title" className="bg-gradient-to-br from-cream to-roseTone-50">
          <div className="mx-auto max-w-5xl px-5 py-16 sm:px-8 sm:py-24">
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-roseTone-600">Project Portfolio</p>
            <h1 id="hero-title" className="mt-3 text-3xl font-extrabold leading-tight sm:text-5xl">
              AI 크리에이터 콘텐츠를
              <br />
              믿을 수 있게 만들고 관리하는 시스템
            </h1>
            <p className="mt-5 max-w-2xl text-base leading-relaxed text-warmGray sm:text-lg">
              한국·일본 대상 AI 라이프스타일 캐릭터 ‘Lovely Yuuka’를 기획하며 겪은 문제를 해결하려고 만든 콘텐츠 제작·검수·자산 관리 프로토타입입니다.
              {owner.name && <> 기획·검수: {owner.name}.</>}
            </p>
            <dl className="mt-8 grid gap-3 sm:grid-cols-3">
              {heroFacts.map((f) => (
                <div key={f.k} className="rounded-2xl border border-ivoryBorder bg-white/80 p-4">
                  <dt className="text-xs font-semibold text-warmGray">{f.k}</dt>
                  <dd className="mt-1 text-sm font-semibold">{f.v}</dd>
                </div>
              ))}
            </dl>
            <div className="mt-8 flex flex-wrap gap-3">
              <a href="#problem" className="rounded-full bg-berry px-5 py-2.5 text-sm font-semibold text-white hover:bg-roseTone-800">
                문제부터 보기
              </a>
              <a href="#progress" className="rounded-full border border-berry/20 bg-white px-5 py-2.5 text-sm font-semibold hover:border-roseTone-500">
                현재 구현 상태
              </a>
            </div>
          </div>
        </section>

        {/* 2. Problem */}
        <Section id="problem" kicker="Problem" title="AI로 만들수록 관리해야 할 것이 늘어났습니다">
          <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {problems.map((p, i) => (
              <li key={p.t} className="rounded-2xl border border-ivoryBorder bg-white p-5">
                <span className="text-2xl font-extrabold text-roseTone-200" aria-hidden="true">
                  {String(i + 1).padStart(2, '0')}
                </span>
                <h3 className="mt-1 font-bold">{p.t}</h3>
                <p className="mt-1 text-sm leading-relaxed text-warmGray">{p.d}</p>
              </li>
            ))}
          </ul>
        </Section>

        {/* 3. Solution */}
        <Section id="solution" kicker="Solution" title="기준 고정 · 전 단계 기록 · 사람 승인">
          <ol className="grid gap-4 md:grid-cols-3">
            {solutions.map((s, i) => (
              <li key={s.t} className="rounded-2xl bg-roseTone-50 p-5">
                <p className="text-sm font-bold text-roseTone-600">STEP {i + 1}</p>
                <h3 className="mt-1 text-lg font-bold">{s.t}</h3>
                <p className="mt-2 text-sm leading-relaxed text-warmGray">{s.d}</p>
              </li>
            ))}
          </ol>
        </Section>

        {/* 4. Prototype */}
        <Section id="prototype" kicker="Prototype" title="제작 과정 전체를 기록하고 사람이 승인하는 흐름">
          <p className="mb-6 text-sm text-warmGray">각 단계의 배지는 실제 구현 수준 그대로입니다.</p>
          <ol className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {flow.map((f, i) => (
              <li key={f.t} className={`rounded-2xl border bg-white p-4 ${f.s === 'plan' ? 'border-dashed border-roseTone-200' : 'border-ivoryBorder'}`}>
                <div className="flex items-center justify-between gap-2">
                  <h3 className="font-bold">
                    <span className="mr-1 text-roseTone-500">{i + 1}.</span>
                    {f.t}
                  </h3>
                  <Badge s={f.s} />
                </div>
                <p className="mt-2 text-sm text-warmGray">{f.d}</p>
              </li>
            ))}
          </ol>
        </Section>

        {/* 5. QA Case */}
        <Section id="qa" kicker="QA Case" title="카페 장면 이미지 1장을 항목별로 검수한 기록">
          <p className="mb-6 max-w-3xl text-sm leading-relaxed text-warmGray">
            공식 얼굴 기준 이미지(448×600)를 해시로 고정하고, 그 기준으로 생성한 첫 이미지를 검수했습니다. AI가 승인하지 않고 사람이 최종 판정하며, 현재 판정 대기 중입니다.
            얼굴 이미지는 공개 승인 전이라 이 페이지에 싣지 않았습니다.
          </p>
          <div className="overflow-x-auto rounded-2xl border border-ivoryBorder bg-white">
            <table className="w-full min-w-[560px] text-left text-sm">
              <caption className="sr-only">생성 이미지 검수 결과</caption>
              <thead className="bg-roseTone-50 text-warmGray">
                <tr>
                  <th scope="col" className="px-4 py-3 font-semibold">검수 항목</th>
                  <th scope="col" className="px-4 py-3 font-semibold">결과</th>
                  <th scope="col" className="px-4 py-3 font-semibold">메모</th>
                </tr>
              </thead>
              <tbody>
                {qaRows.map((r) => (
                  <tr key={r.item} className="border-t border-ivoryBorder">
                    <th scope="row" className="px-4 py-3 font-semibold">{r.item}</th>
                    <td className="px-4 py-3"><Badge s={r.s}>{r.result}</Badge></td>
                    <td className="px-4 py-3 text-warmGray">{r.note}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="mt-4 border-l-2 border-roseTone-200 pl-4 text-sm text-warmGray">
            결과물이 디자인 도구 캔버스에만 남아 원본 파일 내보내기에 실패했습니다. 화면 캡처를 원본으로 대신하지 않고 ‘원본 보관 대기’로 표시했습니다. 근거 없는 유사도 점수는 만들지 않았습니다.
          </p>
        </Section>

        {/* 6. My Role */}
        <Section id="role" kicker="My Role" title="만드는 일과 판단하는 일을 나눴습니다">
          <div className="grid gap-4 md:grid-cols-2">
            <div className="rounded-2xl bg-roseTone-50 p-5">
              <h3 className="font-bold">제가 직접 한 일</h3>
              <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-warmGray">
                {roles.me.map((r) => <li key={r}>{r}</li>)}
              </ul>
            </div>
            <div className="rounded-2xl border border-ivoryBorder bg-white p-5">
              <h3 className="font-bold">AI 도구가 한 일</h3>
              <ul className="mt-3 list-disc space-y-1 pl-5 text-sm text-warmGray">
                {roles.ai.map((r) => <li key={r}>{r}</li>)}
              </ul>
              <p className="mt-3 text-xs text-warmGray">코드를 제가 모두 직접 작성했다고 표현하지 않습니다.</p>
            </div>
          </div>
        </Section>

        {/* 7. Tools */}
        <Section id="tools" kicker="Tools" title="실제로 사용한 도구">
          <dl className="divide-y divide-ivoryBorder rounded-2xl border border-ivoryBorder bg-white">
            {tools.map((t) => (
              <div key={t.g} className="grid gap-1 px-5 py-4 sm:grid-cols-[180px_1fr]">
                <dt className="text-sm font-semibold text-warmGray">{t.g}</dt>
                <dd className="text-sm">{t.v}</dd>
              </div>
            ))}
          </dl>
        </Section>

        {/* 8. Progress */}
        <Section id="progress" kicker="Progress" title={`어디까지 됐는지 (${lastUpdated} 직접 실행 기준)`}>
          <ul className="space-y-3">
            {progress.map((p) => (
              <li key={p.t} className="flex flex-col gap-2 rounded-2xl border border-ivoryBorder bg-white p-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p className="font-semibold">{p.t}</p>
                  <p className="text-sm text-warmGray">{p.evidence}</p>
                </div>
                <Badge s={p.s} />
              </li>
            ))}
          </ul>
          <p className="mt-4 text-sm text-warmGray">서버·계정·결제는 아직 없습니다. 다중 사용자 서비스라고 표현하지 않습니다.</p>
        </Section>

        {/* 9. Learning */}
        <Section id="learning" kicker="Learning" title="예상과 다르게 흘러간 순간에서 배운 것">
          <div className="grid gap-4 lg:grid-cols-3">
            {learnings.map((l) => (
              <article key={l.t} className="rounded-2xl border border-ivoryBorder bg-white p-5">
                <h3 className="font-bold">{l.t}</h3>
                <dl className="mt-3 space-y-3 text-sm">
                  <div><dt className="font-semibold text-roseTone-600">시도</dt><dd className="text-warmGray">{l.tried}</dd></div>
                  <div><dt className="font-semibold text-roseTone-600">예상과 다른 결과</dt><dd className="text-warmGray">{l.result}</dd></div>
                  <div><dt className="font-semibold text-roseTone-600">바꾼 접근</dt><dd className="text-warmGray">{l.change}</dd></div>
                </dl>
              </article>
            ))}
          </div>
        </Section>

        {/* 10. Next Steps */}
        <Section id="next" kicker="Next Steps" title="지금 있는 곳과 가고 싶은 곳">
          <ol className="grid gap-3 md:grid-cols-4">
            {nextSteps.map((n) => (
              <li key={n.t} className={`rounded-2xl p-4 ${n.s === 'done' ? 'bg-roseTone-50' : 'border border-dashed border-roseTone-200 bg-white'}`}>
                <Badge s={n.s}>{n.s === 'done' ? '현재' : '계획'}</Badge>
                <h3 className="mt-2 font-bold">{n.t}</h3>
                <p className="mt-1 text-sm text-warmGray">{n.d}</p>
              </li>
            ))}
          </ol>
          <p className="mt-4 text-sm text-warmGray">‘현재’ 외의 단계는 계획이며 성과가 아닙니다.</p>
        </Section>
      </main>

      <footer className="bg-berry text-roseTone-100">
        <div className="mx-auto max-w-5xl space-y-2 px-5 py-10 text-sm sm:px-8">
          <p className="font-semibold text-white">YUUKA AI CHANNEL OS · Project Portfolio</p>
          <p>이 페이지의 코드는 Claude Code로 작성했고, 문제 정의·내용 검수·공개 여부는 직접 결정했습니다.</p>
          <p>얼굴 이미지는 공개 승인 전이라 싣지 않았습니다. 최종 수정 {lastUpdated}.</p>
          {owner.links.length > 0 && (
            <ul className="flex flex-wrap gap-4 pt-2">
              {owner.links.map((l) => (
                <li key={l.href}>
                  <a className="underline underline-offset-4" href={l.href} target="_blank" rel="noreferrer">
                    {l.label}
                  </a>
                </li>
              ))}
            </ul>
          )}
        </div>
      </footer>
    </div>
  )
}

export default App
