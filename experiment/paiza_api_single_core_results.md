# paiza.IO API Single-Core Measurement Results

## Conditions

- Source: `experiment/minesweeper_solver.cpp`
- Execution environment: paiza.IO API
- CPU configuration: 1 thread
- Evaluation boards: 10,000 boards
- Input: `board01.txt` through `board11.txt`
- The 10,000-board file exceeded the API input-size limit, so the input was split into 11 files and executed separately.
- All 11 API executions completed successfully.

## Results

```text
boards_processed  10000
safe_opened       1068459
mines_opened      10777
total_score       9457.1848
```

## Total Execution Time

| Processing section | Total time |
|---|---:|
| Overall execution | 2.136724 s |
| Deterministic inference | 0.763207 s |
| Local conditions | 0.430663 s |
| Global mine-count condition | 0.000179 s |
| Subset rules | 0.037325 s |
| Probabilistic inference | 1.036318 s |
| Connected-component division | 0.162456 s |
| Mine-placement enumeration | 0.609376 s |
| Combination of placement distributions | 0.088962 s |
| Probability calculation and minimum-risk cell selection | 0.024725 s |

## Notes

The probabilistic inference phase is the largest contributor to execution time. Within that phase, mine-placement enumeration takes the most time.

The reported section times are cumulative measurements from the 11 input files. The overall time is the sum of the 11 API-reported program elapsed times.
