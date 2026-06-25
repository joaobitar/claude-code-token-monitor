function New-TestPayload {
    param(
        [long]$BudgetTokens     = 200000,
        [long]$InputTokens      = 0,
        [long]$OutputTokens     = 0,
        [long]$CacheWriteTokens = 0,
        [long]$CacheReadTokens  = 0,
        [int]$UsedPercentage    = 0,
        [int]$Pct5h             = 0,
        [int]$PctWeek           = 0,
        [long]$ResetsAt         = 0,
        [double]$TotalCostUsd   = 0,
        [string]$ModelName      = "Claude Sonnet 4.6",
        [string]$ProjectDir     = ""
    )

    return @{
        context_window = @{
            budget_tokens                = $BudgetTokens
            total_input_tokens           = $InputTokens
            total_output_tokens          = $OutputTokens
            cache_creation_input_tokens  = $CacheWriteTokens
            cache_read_input_tokens      = $CacheReadTokens
            used_percentage              = $UsedPercentage
        }
        cost = @{
            total_cost_usd = $TotalCostUsd
        }
        model = @{
            display_name = $ModelName
        }
        rate_limits = @{
            five_hour = @{
                used_percentage = $Pct5h
                resets_at       = $ResetsAt
            }
            seven_day = @{
                used_percentage = $PctWeek
            }
        }
        workspace = @{
            project_dir = $ProjectDir
        }
    }
}
