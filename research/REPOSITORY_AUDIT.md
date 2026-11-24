# Repository Audit: Hierarchical Self-Improvement (HSI) Framework

**Project**: Confidence-Aware Hierarchical Self-Improving Agents  
**Target Benchmark**: BALROG (BabyAI, Crafter, TextWorld)  
**Date of Audit**: 2026-11-24  
**Auditor**: Senior AI Research Engineering Assistant  

---

## 1. Repository Architecture & Directory Structure

The HSI codebase implements an evolvable task harness around a frozen LLM backbone. The architecture is cleanly stratified into three distinct layers:
1. **Task Harness Scope ($H$)**: Executes actions on the benchmark environment. Fixed boundary entry signature: `using_harness(agent, task)`.
2. **Evolver Scope**: Iteratively modifies harness code (`harness.py`, `prompts.py`, `hooks.py`, `context.py`), performs dev/val evaluations, and commits diverse candidates.
3. **Meta-Evolver Scope ($\Sigma$)**: Outer anchor that rewrites evolver strategies (`evolution/select_seed.py`, `evolution/select_commit.py`, `evolution/strategies/`) and executes final best-version selection (`select_best.py`).

### Verified Workspace Layout
```
hsi/
├── .env                               # LLM provider & API credentials
├── config.yaml                        # Master experiment configuration
├── main.py                            # Primary entry point: manages the 5-stage loop
├── main_init.py                       # Baseline runner: evaluates initial unevolved harness
├── main_final.py                      # Post-evolution evaluator: evaluates exported best harness
├── run_tests.py                       # Standalone sanity test suite (imports, state, LCB, git)
├── requirements.txt                   # Dependency manifest
├── benchmark_config_goal/             # Benchmark suite YAML configs & goal.md specifications
│   ├── balrog_babyai/                 # BabyAI suite configuration
│   ├── balrog_crafter/                # Crafter suite configuration
│   ├── balrog_textworld/              # TextWorld suite configuration
│   ├── balrog_minihack/               # MiniHack suite configuration
│   ├── balrog_nle/                    # NetHack suite configuration
│   └── balrog_babaisai*/              # BabaIsAI sub-suite configurations
├── godel_harness_init/                # Frozen initial harness templates
│   ├── balrog_babyai/                 # BabyAI initial harness template
│   └── balrog/                        # Unified BALROG harness template
├── godel_evolution_init/              # Frozen meta-evolver templates (outer anchor)
│   ├── select_seed.py                 # Hypothesis & seed commit selector
│   ├── select_commit.py               # Iteration commit pool nudger
│   ├── select_best.py                 # Final deployment selector
│   └── strategies/                    # Seed exploration strategies (greedy, recursive, ensemble)
├── src/
│   ├── benchmark/                     # Benchmark evaluation adapters & environments
│   │   ├── adapter.py                 # Base BenchmarkEvaluatorAdapter interface
│   │   ├── config.py                  # BenchmarkConfig dataclass
│   │   └── balrog/                    # BALROG adapter & environment drivers
│   │       ├── adapter.py             # BalrogAdapter (_calculate_reward, metrics aggregation)
│   │       ├── evaluator.py           # BalrogEvaluator (task loading, episode rollout)
│   │       └── environments/          # Environment wrappers (babyai_text, crafter, etc.)
│   └── react_loop/                    # Core HSI engine
│       ├── agent.py                   # GodelAgent (LLM interactions, react loop)
│       ├── evolve.py                  # EvolveHelper (main evolution, commit pooling)
│       ├── meta_evolve.py             # MetaEvolveHelper (meta-evolution phase)
│       ├── seed_selection.py          # Seed selection react loop & candidate assembly
│       ├── submit_best.py             # Final best-agent validation react loop
│       ├── state.py                   # AgentState, ActionType, LCB reward math
│       ├── knowledge_graph.py         # EvolutionKnowledgeGraph (nodes, edges, pruning)
│       ├── context_persistence.py     # Checkpointing & resumption support
│       ├── evolution_prompt.py        # System and iteration user prompt builders
│       ├── actions/
│       │   ├── agent_action.py        # Action execution, tool registry, file scanning
│       │   └── agent_evaluator.py     # EvaluatorMixin: evaluate() tool, harness snapshots
│       ├── git_version/
│       │   └── controller.py          # GitController & EvolutionTracker (records.jsonl)
│       ├── utils/
│       │   ├── harness_loader.py      # HarnessLoader: isolated, fresh-import runtime
│       │   └── tools.py               # OpenAI function tool definitions
│       └── visualization/             # D3.js interactive commit graph renderer
└── evolution_results/                 # Output directories per suite run
```

---

## 2. Core Execution Flow

The top-level execution lifecycle in `main.py` proceeds as follows:

```
[Load config.yaml & .env]
          │
          ▼
[Initialize Run Directory & Git Repo from godel_harness_init/]
          │
          ▼
┌────────────────────────────────────────────────────────┐
│ For iteration t = 1 ... T:                             │
│                                                        │
│  Stage 1: Seed Selection (seed_selection.py)           │
│    Reads knowledge graph G_{t-1}, historical tracker,   │
│    emits hypothesis h_t, selects seed commit S_t.      │
│                                                        │
│  Stage 2: Main Evolution (evolve.py)                   │
│    ReAct agent edits harness files (read/edit/write)    │
│    Evaluates candidate code via evaluate()             │
│    Records ephemeral plan.md and persistent lessons    │
│                                                        │
│  Stage 3: Commit Selection (evolve.py + select_commit) │
│    Nudge phase: agent calls finalize_commit_pool()     │
│    Squashes changes into 2-5 diverse Git commits       │
│    Aligns code snapshots with verified rewards         │
│                                                        │
│  Stage 4: Meta-Evolution (meta_evolve.py)              │
│    Inspects iteration representative harness           │
│    Rewrites select_seed.py / select_commit.py          │
└────────────────────────────────────────────────────────┘
          │
          ▼
  Stage 5: Best-Version Selection (submit_best.py)
    Validates candidates on validation set; exports best harness
          │
          ▼
  Held-Out Evaluation (main.py: run_test_set_eval)
    Evaluates final exported harness on test split over multiple repeats
```

---

## 3. Verified Integration Points

### 3.1 Task Reward Calculation
* **Per-Task Episode Rollout**:
  * **File**: `src/benchmark/balrog/evaluator.py`
  * **Method**: `BalrogEvaluator.evaluate_task(task: BenchmarkTask, solver: Callable) -> TaskEvaluationResult` (lines 132–206)
  * **Behavior**: Runs `num_episodes` rollouts. Calculates raw mean progression `avg_progression = sum(episode_progressions) / len(episode_progressions)` (line 170). Calculates Lower Confidence Bound `lcb_progression = lower_confidence_bound(episode_progressions, z=lcb_zscore)` (line 179).
* **Benchmark Aggregated Reward**:
  * **File**: `src/benchmark/balrog/adapter.py`
  * **Method**: `BalrogAdapter._calculate_reward(results, evaluate_seq, iteration, eval_mode)` (lines 115–215)
  * **Behavior**: For `dev` and `val` modes, aggregated headline reward is the mean of per-task LCB values (`reward = total_progression / len(results)`). For `test` mode, it uses unpenalized raw progression (`reward = total_raw_progression / len(results)`).
* **Statistical LCB Function**:
  * **File**: `src/react_loop/state.py`
  * **Function**: `lower_confidence_bound(values: List[float], z: float = 1.0) -> float` (lines 115–131)
  * **Formula**: $\mu - z \cdot \frac{\sigma}{\sqrt{n}}$ (returns $\mu$ if $n < 2$ or $\sigma = 0$).

### 3.2 Evaluation Result Storage
* **In-Memory Snapshots**:
  * **File**: `src/react_loop/actions/agent_evaluator.py` (lines 306–380)
  * Code snapshot is indexed by `code_hash` in `self.state.code_snapshots[code_hash]`.
  * Evaluation metadata is appended to `self.state.evaluation_snapshots.append([code_hash, snapshot_reward, eval_mode, exec_errors, modified_snapshot, mods_snapshot])` (lines 370–372).
  * Rewards and metrics are updated via `self.state.update_reward(reward, eval_mode)` and `self.state.update_metrics(metrics)`.
* **On-Disk Harness Version History**:
  * **File**: `src/react_loop/actions/agent_evaluator.py` (lines 64–118)
  * `_persist_harness_history(current_iteration, evaluate_seq, code_hash, snapshot)` writes copies of running harness files to `.evolution_context/main_evolve/harness_history/iter_<it>/eval_<seq>_<hash>/`.
* **Evaluation JSON Logs**:
  * **File**: `src/benchmark/adapter.py` (lines 526–617)
  * Writes `eval_logs/eval_{seq:03d}_{eval_mode}.json`, `condensed_eval_{seq:03d}.json`, and raw per-task episode logs.
* **Persistent Git Tracker**:
  * **File**: `src/react_loop/git_version/controller.py` (lines 888–928)
  * `EvolutionTracker.add_record(record)` appends records to `records.jsonl` and updates `evolution_metadata.json`.

### 3.3 Evolver Feedback Delivery
* **Synchronous Tool Feedback**:
  * **File**: `src/react_loop/actions/agent_evaluator.py` (lines 381–484)
  * `evaluate()` formats output returned directly to the agent's ReAct context:
    * `val` mode: minimal reward string (`Validation Evaluation (reward-only): reward=<score> [code_hash: <hash>]`).
    * `dev` mode:
      * Harness crashes return full traceback via `_format_execution_error_details(metrics)` (lines 451–464).
      * LLM summary returns diagnostic synthesis via `_summarize_evaluation(reward, metrics)` (lines 473–478).
      * Standard mode returns list of failed tasks via `_format_failed_tasks_only(...)`.
* **Inter-Iteration Context**:
  * **File**: `src/react_loop/evolution_prompt.py` (lines 142–245)
  * `get_iteration_begin_prompt()` injects prior iteration summaries, reward progression, Knowledge Graph summary table, seed hypothesis, and `BOOTSTRAP.md` lessons.

### 3.4 Candidate Selection & Acceptance Lifecycle
* **Nomination (Nudge Phase)**:
  * **File**: `src/react_loop/evolve.py` (lines 1545–1650)
  * `_select_commit_version()` prompts the agent to call `finalize_commit_pool(code_hashes=[...])` choosing 2–5 diverse versions evaluated during the iteration.
* **Verification & Acceptance**:
  * **File**: `src/react_loop/evolve.py` (lines 1903–2190)
  * `commit_iteration()` executes:
    1. Deduplication of candidate code hashes (lines 1951–1961).
    2. Exact disk state restoration from `self._restore_code_snapshot(ch)` (lines 2008–2010).
    3. Reward verification and re-alignment via `self._align_reward_with_committed_code(ch)` (lines 2034–2046).
    4. Git commit generation (`git commit -m "iter_X: pool=i/N ..."`) and tagging (lines 2064–2095).
    5. Node registration in `EvolutionKnowledgeGraph` and `EvolutionTracker`.

### 3.5 Historical Candidate Evaluation
* **Seed Candidate Evaluation**:
  * **File**: `src/react_loop/seed_selection.py` (lines 734–770, 1168–1212)
  * Evaluates historical candidate versions or ensemble fusions during seed selection when `seed_eval_enabled: true`.
* **Final Deployment Selection (Submit-Best)**:
  * **File**: `src/react_loop/submit_best.py` (lines 207–215, 335–420)
  * Evaluates candidates on validation set. Strictly rejects candidates whose own commit was not directly evaluated (lines 401–412).
* **Held-Out Test Set**:
  * **File**: `main.py` (lines 380–450) and `main_final.py` (lines 180–240)
  * Evaluates final exported harness across repeated test trials.

---

## 4. Proposed Integration Architecture for Research Extensions

```
                                  EVALUATION RESULTS
                                          │
                                          ▼
                         ┌─────────────────────────────────┐
                         │   Feedback Reliability          │
                         │   Estimator                     │
                         │   (src/react_loop/reliability/) │
                         └─────────────────────────────────┘
                                          │
                     Reliability Metrics  │ (Completeness, Variance, Hash Integrity)
                                          ▼
                         ┌─────────────────────────────────┐
                         │   Confidence-Aware              │
                         │   Evolution Controller          │
                         │   (ALLOW / REQUEST_MORE / DEFER)│
                         └─────────────────────────────────┘
                                          │
                     Reliable Candidates  │
                                          ▼
                         ┌─────────────────────────────────┐
                         │   Regression-Aware Gate         │
                         │   Paired Candidate vs Incumbent │
                         │   Validation on Task Set        │
                         └─────────────────────────────────┘
                                          │
                              ACCEPT / REJECT Decision
                                          ▼
                         ┌─────────────────────────────────┐
                         │   commit_iteration()            │
                         │   (Git Tracker & Knowledge      │
                         │    Graph Persistence)           │
                         └─────────────────────────────────┘
```

### Proposed Modules
1. `src/react_loop/reliability/models.py`: Data models (`ReliabilityEvidence`, `ReliabilityResult`, `RegressionResult`).
2. `src/react_loop/reliability/estimator.py`: Statistical evidence completeness and consistency estimation.
3. `src/react_loop/reliability/controller.py`: Decision policy controlling feedback sufficiency.
4. `src/react_loop/reliability/regression_gate.py`: Paired evaluation comparing candidate harness against incumbent on identical task conditions.
5. `src/react_loop/reliability/logger.py`: Structured JSONL evidence logging.

---

## 5. Potential Compatibility Risks & Mitigation

| Risk | Description | Mitigation Strategy |
|---|---|---|
| **Code-Hash Drift** | `sys.modules` caching or intermediate working tree edits causing candidate evaluated code to differ from committed code. | Utilize the established `HarnessLoader` unique package name pattern and `_compute_code_hash(return_contents=True)`. |
| **Silent Benchmark Degradation** | A candidate scoring high on average due to an outlier jackpot on one task while regressing across others. | Implement paired task-level comparison in `regression_gate.py` with strict regression tolerances. |
| **Computational Budget Explosion** | Repeated candidate validation doubling or tripling inference calls. | Enforce strict configurable validation caps (`max_eval_budget`, early stopping on failure). |
| **Breaking Baseline Compatibility** | Research extensions altering core HSI invariants when disabled. | Keep all extensions modular, isolated under `src/react_loop/reliability/`, and gated by `config.yaml` flags (defaulting to existing behavior). |

---

## 6. Audit Conclusion & Baseline Status
* The core framework is intact: `run_tests.py` (6/6) and `pytest src/react_loop/tests` (61/61) are 100% passing.
* Integration points are verified against source code without ambiguity.
* Prerequisites for BabyAI benchmark execution identified (Minigrid package requirement and live LLM endpoint configuration in `.env`).

