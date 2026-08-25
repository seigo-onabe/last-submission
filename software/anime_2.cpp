// HTMLトレース出力対応版（既存の minesweeper_solver.cpp は変更しない）。
// build: g++ -std=c++17 -O2 -pthread anime_2.cpp -o minesweeper_solver_animation
// run:   ./minesweeper_solver_animation [--html trace.html] [board.txt]
#include <array>
#include <atomic>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <exception>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <istream>
#include <limits>
#include <mutex>
#include <numeric>
#include <ostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

// 標準ヘッダを先読みしてから private を公開し、既存の補助関数を利用する。
#define private public
#define main minesweeper_original_main
#include "minesweeper_solver.cpp"
#undef main
#undef private

namespace animation {
using namespace minesweeper;
enum class Kind { Initial, Deterministic, ChooseCell };
struct Step { int cell; Kind kind; double probability; bool exact; std::string cells; };
struct Trace { std::string name; int w, h, mines; std::vector<Step> steps; };

char stateChar(CellState state, std::uint8_t clue) {
  if (state == CellState::kUnknown) return '?';
  if (state == CellState::kQueuedSafe) return 's';
  if (state == CellState::kKnownMine) return 'f';
  if (state == CellState::kOpenMine) return 'x';
  return static_cast<char>('0' + clue);
}
const char* label(Kind kind) {
  return kind == Kind::Initial ? "Initial" :
         kind == Kind::Deterministic ? "Deterministic" : "ChooseCell";
}
void record(Trace& trace, const Solver& solver, int cell, Kind kind,
            double p = -1.0, bool exact = false) {
  Step step{cell, kind, p, exact, ""};
  for (int i = 0; i < solver.cellCount(); ++i)
    step.cells += stateChar(solver.states_[i], solver.clues_[i]);
  trace.steps.push_back(std::move(step));
}
void openAndRecord(Solver& solver, QueryEngine& engine, Trace& trace, int cell,
                   Kind kind, double p = -1.0, bool exact = false) {
  solver.applyReveals(engine.select(cell));
  record(trace, solver, cell, kind, p, exact);
}

SolverStatistics solveWithTrace(Solver& solver, QueryEngine& engine, Trace& trace) {
  SolverStatistics stats;
  const int first = solver.index(0, 0);
  ++stats.guesses;
  openAndRecord(solver, engine, trace, first, Kind::Initial);
  if (solver.states_[first] != CellState::kOpenMine && solver.clues_[first] != 0) {
    const std::array<int, 4> corners = {
      solver.index(0,0), solver.index(solver.width_-1,0),
      solver.index(0,solver.height_-1), solver.index(solver.width_-1,solver.height_-1)};
    for (int i = 1; i < 4; ++i) {
      bool duplicate = false;
      for (int j = 0; j < i; ++j) duplicate |= corners[i] == corners[j];
      if (duplicate || solver.states_[corners[i]] != CellState::kUnknown) continue;
      ++stats.guesses;
      openAndRecord(solver, engine, trace, corners[i], Kind::Initial);
      if (solver.states_[corners[i]] == CellState::kOpenMine ||
          solver.clues_[corners[i]] == 0) break;
    }
  }
  while (true) {
    int safe = solver.popSafeCell();
    if (safe >= 0) {
      openAndRecord(solver, engine, trace, safe, Kind::Deterministic);
      continue;
    }
    solver.propagateDeterministicRules();
    safe = solver.popSafeCell();
    if (safe >= 0) {
      openAndRecord(solver, engine, trace, safe, Kind::Deterministic);
      continue;
    }
    if (solver.opened_safe_ == solver.cellCount() - solver.total_mines_) return stats;
    const GuessDecision d = solver.probability_engine_.chooseCell(
      solver.width_, solver.height_, solver.total_mines_, solver.known_mines_,
      solver.states_, solver.clues_);
    if (d.cell < 0) throw std::runtime_error("推測対象セルを選択できません");
    if (solver.cellCount() > 200 && solver.total_mines_ * 100 < solver.cellCount() * 20 &&
        solver.opened_safe_ * 2 >= solver.cellCount() - solver.total_mines_) {
      const int n = minesweeper::unknownNeighborCount(
        d.cell, solver.width_, solver.height_, solver.states_);
      const double advantage = solver.total_mines_ - solver.cellCount() * d.mine_probability +
        solver.total_mines_ * (1.0 - d.mine_probability) *
        MINESWEEPER_INFORMATION_K_SCALE * n;
      if (advantage < 0.0) return stats;
    }
    ++stats.guesses;
    stats.exact_guesses += d.exact;
    stats.approximate_guesses += !d.exact;
    openAndRecord(solver, engine, trace, d.cell, Kind::ChooseCell,
                  d.mine_probability, d.exact);
  }
}

std::string quote(const std::string& text) {
  std::string result = "\"";
  for (char c : text) {
    if (c == '"' || c == '\\') result += '\\';
    if (c == '\n') result += "\\n";
    else if (c == '\r') result += "\\r";
    else result += c;
  }
  return result + '"';
}
void writeHtml(const std::string& path, const std::vector<Trace>& traces) {
  std::ofstream out(path);
  if (!out) throw std::runtime_error("HTMLを作成できません: " + path);
  out << R"HTML(<!doctype html>
<meta charset="utf-8">
<title>Minesweeper Solver Trace</title>
<style>
:root{--bg:#111827;--surface:#1f2937;--card:#374151;--border:#4b5563;
      --text:#f9fafb;--muted:#9ca3af;--accent:#3b82f6;--radius:8px;
      --mono:"JetBrains Mono","Fira Code",monospace}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font-family:system-ui,sans-serif;
     padding:24px;min-height:100vh}
h1{font-size:1.4rem;font-weight:700;margin-bottom:18px;color:#e5e7eb;
   letter-spacing:.02em}
/* controls */
.ctrl{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:14px}
select,button{padding:6px 12px;border-radius:6px;border:1px solid var(--border);
              background:var(--surface);color:var(--text);font:inherit;cursor:pointer}
select:hover,button:hover{border-color:var(--accent)}
button.primary{background:var(--accent);border-color:var(--accent);
               color:#fff;font-weight:600}
.range-wrap{display:flex;align-items:center;gap:6px;flex:1;min-width:160px}
input[type=range]{flex:1;accent-color:var(--accent)}
.spd-wrap{display:flex;align-items:center;gap:6px;font-size:.8rem;color:var(--muted)}
/* info panel */
.info-panel{background:var(--surface);border:1px solid var(--border);
            border-radius:var(--radius);padding:12px 16px;margin-bottom:14px;
            display:flex;gap:16px;align-items:center;flex-wrap:wrap}
.badge{padding:3px 10px;border-radius:20px;font-size:.78rem;font-weight:700;
       letter-spacing:.04em;white-space:nowrap}
.badge-initial{background:#1d4ed8;color:#dbeafe}
.badge-det{background:#065f46;color:#d1fae5}
.badge-guess{background:#92400e;color:#fef3c7}
.step-counter{font-family:var(--mono);font-size:.85rem;color:var(--muted)}
.prob-wrap{display:flex;align-items:center;gap:8px;flex:1;min-width:180px}
.prob-label{font-size:.8rem;color:var(--muted);white-space:nowrap}
.prob-bar-bg{flex:1;height:8px;background:var(--card);border-radius:4px;overflow:hidden}
.prob-bar{height:100%;border-radius:4px;transition:width .15s,background .15s}
.prob-val{font-family:var(--mono);font-size:.8rem;color:var(--text);white-space:nowrap}
/* grid */
#grid-wrap{overflow:auto}
#grid{display:grid;gap:2px;background:var(--border);border:2px solid var(--border);
      border-radius:6px;width:max-content;margin-top:2px}
.c{width:30px;height:30px;display:grid;place-items:center;font-weight:700;
   font-size:.82rem;font-family:var(--mono);transition:background .1s}
.u{background:#374151;color:var(--muted)}
.s{background:#14532d;color:#86efac}
.f{background:#78350f;color:#fde68a}
.x{background:#7f1d1d;color:#fca5a5}
.n0{background:#1f2937;color:transparent}
.n1{background:#1e3a5f;color:#60a5fa}
.n2{background:#14532d;color:#4ade80}
.n3{background:#7f1d1d;color:#f87171}
.n4{background:#1e1b4b;color:#818cf8}
.n5{background:#7c2d12;color:#fdba74}
.n6{background:#164e63;color:#22d3ee}
.n7{background:#374151;color:#f9fafb}
.n8{background:#4b5563;color:#e5e7eb}
.hit{outline:3px solid #facc15;outline-offset:-3px;z-index:1;position:relative}
/* legend */
.legend{display:flex;gap:10px;flex-wrap:wrap;margin-top:12px}
.leg-item{display:flex;align-items:center;gap:5px;font-size:.75rem;color:var(--muted)}
.leg-box{width:14px;height:14px;border-radius:3px}
</style>
<h1>🧨 Minesweeper Solver Trace</h1>
<div class="ctrl">
  <select id="b"></select>
  <button onclick="go(-1)">◀ 前へ</button>
  <button id="play" class="primary" onclick="toggle()">▶ 再生</button>
  <button onclick="go(1)">次へ ▶</button>
  <div class="range-wrap"><input id="r" type="range" min="0" value="0"></div>
  <div class="spd-wrap">
    速度<input id="spd" type="range" min="100" max="2000" value="500" step="100"
               style="width:80px">
    <span id="spd-val">0.5s</span>
  </div>
</div>
<div class="info-panel">
  <span id="badge" class="badge"></span>
  <span id="step-ctr" class="step-counter"></span>
  <div class="prob-wrap" id="prob-wrap">
    <span class="prob-label">地雷確率</span>
    <div class="prob-bar-bg"><div class="prob-bar" id="prob-bar"></div></div>
    <span class="prob-val" id="prob-val"></span>
  </div>
</div>
<div id="grid-wrap"><div id="grid"></div></div>
<div class="legend">
  <div class="leg-item"><div class="leg-box" style="background:#374151"></div>未開</div>
  <div class="leg-item"><div class="leg-box" style="background:#14532d"></div>安全確定待ち</div>
  <div class="leg-item"><div class="leg-box" style="background:#78350f"></div>地雷確定</div>
  <div class="leg-item"><div class="leg-box" style="background:#7f1d1d"></div>地雷(開放)</div>
  <div class="leg-item"><div class="leg-box" style="outline:3px solid #facc15;width:14px;height:14px;border-radius:3px"></div>今回選択</div>
</div>
<script>const T=)HTML";
  out << '[';
  for (std::size_t b = 0; b < traces.size(); ++b) {
    if (b) out << ',';
    const Trace& t = traces[b];
    out << "{n:" << quote(t.name) << ",w:" << t.w << ",h:" << t.h << ",s:[";
    for (std::size_t i = 0; i < t.steps.size(); ++i) {
      if (i) out << ',';
      const Step& s = t.steps[i];
      out << "{c:" << s.cell << ",k:" << quote(label(s.kind)) << ",p:"
          << std::setprecision(17) << s.probability << ",e:" << (s.exact?"true":"false")
          << ",v:" << quote(s.cells) << '}';
    }
    out << "]}";
  }
  out << R"HTML(];
let bi=0,si=0,timer,iv=500;
const B=document.querySelector('#b'),R=document.querySelector('#r');
const SpdEl=document.querySelector('#spd'),SpdVal=document.querySelector('#spd-val');
T.forEach((t,i)=>B.add(new Option(t.n||('board '+i),i)));
const numClass=v=>v==='0'?'n0':v==='1'?'n1':v==='2'?'n2':v==='3'?'n3':
                    v==='4'?'n4':v==='5'?'n5':v==='6'?'n6':v==='7'?'n7':'n8';
function draw(){
  const t=T[bi],s=t.s[si];
  R.max=Math.max(0,t.s.length-1); R.value=si;
  // badge
  const badge=document.querySelector('#badge');
  badge.textContent=s.k;
  badge.className='badge '+(s.k==='Initial'?'badge-initial':s.k==='Deterministic'?'badge-det':'badge-guess');
  // step counter
  document.querySelector('#step-ctr').textContent=
    t.n+' — ステップ '+(si+1)+' / '+t.s.length;
  // probability bar
  const pw=document.querySelector('#prob-wrap');
  if(s.p<0){pw.style.display='none'}else{
    pw.style.display='flex';
    const pct=(s.p*100);
    const bar=document.querySelector('#prob-bar');
    bar.style.width=pct+'%';
    bar.style.background=pct<20?'#22c55e':pct<50?'#eab308':'#ef4444';
    document.querySelector('#prob-val').textContent=
      pct.toFixed(2)+'%'+(s.e?' (exact)':' (approx)');
  }
  // grid
  const g=document.querySelector('#grid');
  g.style.gridTemplateColumns='repeat('+t.w+',30px)';
  g.textContent='';
  [...s.v].forEach((v,i)=>{
    const d=document.createElement('div');
    let cls='c ';
    if(v==='?') cls+='u';
    else if(v==='s') cls+='s';
    else if(v==='f') cls+='f';
    else if(v==='x') cls+='x';
    else cls+=numClass(v);
    if(i===s.c) cls+=' hit';
    d.className=cls;
    d.textContent=v==='0'||v==='?'?'':v==='s'?'✓':v==='f'?'⚑':v==='x'?'💥':v;
    g.append(d);
  });
}
function go(x){si=Math.max(0,Math.min(T[bi].s.length-1,si+x));draw();}
B.onchange=()=>{bi=+B.value;si=0;draw();};
R.oninput=()=>{si=+R.value;draw();};
SpdEl.oninput=()=>{iv=+SpdEl.value;SpdVal.textContent=(iv/1000).toFixed(1)+'s';
  if(timer){stop();play();}};
function stop(){if(timer){clearInterval(timer);timer=0;}
  document.querySelector('#play').textContent='▶ 再生';
  document.querySelector('#play').className='primary';}
function play(){stop();timer=setInterval(()=>{
  if(si>=T[bi].s.length-1)stop();else go(1);},iv);
  document.querySelector('#play').textContent='■ 停止';
  document.querySelector('#play').className='';}
function toggle(){timer?stop():play();}
document.addEventListener('keydown',e=>{
  if(e.key==='ArrowRight'){stop();go(1);}
  else if(e.key==='ArrowLeft'){stop();go(-1);}
  else if(e.key===' '){e.preventDefault();toggle();}
});
draw();
</script>)HTML";
}
struct Options { std::string input = "board.txt", html = "minesweeper_trace.html"; };
Options parse(int argc, char** argv) {
  Options o; bool has_input = false;
  for (int i=1;i<argc;++i) {
    std::string_view a=argv[i];
    if (a=="--html") { if (++i>=argc) throw std::runtime_error("--htmlにはパスが必要です"); o.html=argv[i]; }
    else if (!a.empty() && a.front()=='-') throw std::runtime_error("不明なオプションです");
    else if (!has_input) { o.input=argv[i]; has_input=true; }
    else throw std::runtime_error("入力ファイルは1つだけ指定できます");
  }
  return o;
}
}  // namespace animation

int main(int argc, char** argv) {
  using namespace minesweeper; using namespace animation;
  try {
    const animation::Options o=parse(argc,argv);
    std::ifstream input(o.input,std::ios::binary);
    if (!input) throw std::runtime_error("入力ファイルを開けません: "+o.input);
    FastReader reader(readEntireFile(input)); std::vector<Trace> traces; Board board;
    while (readBoard(reader,board)) {
      QueryEngine engine(board); Solver solver(board.width,board.height,board.total_mines);
      Trace t{board.name,board.width,board.height,board.total_mines,{}};
      solveWithTrace(solver,engine,t); traces.push_back(std::move(t));
    }
    writeHtml(o.html,traces);
    std::cout<<"html_output       "<<o.html<<'\n';
  } catch (const std::exception& e) { std::cerr<<"error: "<<e.what()<<'\n'; return 1; }
}