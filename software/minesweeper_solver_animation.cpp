// HTMLトレース出力対応版（既存の minesweeper_solver.cpp は変更しない）。
// build: g++ -std=c++17 -O2 -pthread minesweeper_solver_animation.cpp -o minesweeper_solver_animation
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
  out << R"HTML(<!doctype html><meta charset="utf-8"><title>Minesweeper trace</title>
<style>body{font-family:system-ui;margin:24px;background:#f6f8fb}.bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap}button,select,input{padding:6px;font:inherit}#grid{display:grid;gap:2px;background:#344;margin-top:14px;width:max-content}.c{width:27px;height:27px;display:grid;place-items:center;background:white;font-weight:bold}.u{background:#bbc4d0}.s{background:#d6f5d4}.f{background:#ffd5a1}.x{background:#ffb0b0}.hit{outline:3px solid #2563eb;outline-offset:-3px}</style>
<h1>Minesweeper Solver Trace</h1><div class="bar"><select id="b"></select><button onclick="go(-1)">◀</button><button id="play" onclick="toggle()">▶ 再生</button><button onclick="go(1)">▶</button><input id="r" type="range" min="0" value="0"></div><p id="info"></p><div id="grid"></div>
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
  out << R"HTML(];let bi=0,si=0,timer;const B=document.querySelector('#b'),R=document.querySelector('#r');T.forEach((t,i)=>B.add(new Option(t.n||('board '+i),i)));
function draw(){let t=T[bi],s=t.s[si];R.max=Math.max(0,t.s.length-1);R.value=si;document.querySelector('#info').textContent=t.n+' / '+(si+1)+' / '+t.s.length+' : '+s.k+(s.p<0?'':' / mine probability '+(100*s.p).toFixed(4)+'%'+(s.e?' (exact)':' (approximate)'));let g=document.querySelector('#grid');g.style.gridTemplateColumns='repeat('+t.w+',27px)';g.textContent='';[...s.v].forEach((v,i)=>{let d=document.createElement('div');d.className='c '+(v==='?'?'u':v==='s'?'s':v==='f'?'f':v==='x'?'x':'');d.textContent=v==='0'||v==='?'?'':v==='s'?'✓':v==='f'?'⚑':v==='x'?'×':v;if(i===s.c)d.classList.add('hit');g.append(d)})}function go(x){si=Math.max(0,Math.min(T[bi].s.length-1,si+x));draw()}B.onchange=()=>{bi=+B.value;si=0;draw()};R.oninput=()=>{si=+R.value;draw()};function toggle(){let p=document.querySelector('#play');if(timer){clearInterval(timer);timer=0;p.textContent='▶ 再生'}else{p.textContent='■ 停止';timer=setInterval(()=>{if(si>=T[bi].s.length-1)toggle();else go(1)},500)}}draw();</script>)HTML";
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
