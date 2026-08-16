local ADDON_NAME, Addon = ...

local benchmarkFrame = CreateFrame("Frame")
local state
local previousResult
local lastResult

local function Percentile(sorted, fraction)
    if #sorted == 0 then return 0 end
    local index = math.max(1, math.min(#sorted, math.ceil(#sorted * fraction)))
    return sorted[index] * 1000
end

local function GatherAddonCPU()
    local result = { total = 0, top = {} }
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and
        Enum and Enum.AddOnProfilerMetric) then
        return result
    end

    local metric = Enum.AddOnProfilerMetric.RecentAverageTime
    for index = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(index)
        if name and C_AddOns.IsAddOnLoaded(name) then
            local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
            value = ok and tonumber(value) or 0
            if value and value > 0 then
                result.total = result.total + value
                result.top[#result.top + 1] = { name = name, ms = value }
            end
        end
    end
    table.sort(result.top, function(a, b) return a.ms > b.ms end)
    return result
end

local function FormatChange(current, old, lowerIsBetter)
    if not old or old == 0 then return "n/a" end
    local change = (current - old) / old * 100
    if lowerIsBetter then change = -change end
    local color = change >= 0 and "|cff55ff88" or "|cffff7777"
    return string.format("%s%+.1f%%|r", color, change)
end

local function PrintResult(result)
    Addon.Print(string.format(
        "Benchmark [%s] — %.1fs, %d frames",
        result.profile, result.duration, result.frames
    ))
    Addon.Print(string.format(
        "Avg %.1f FPS / %.2f ms | P95 %.2f ms | P99 %.2f ms | approx. 1%% low %.1f FPS",
        result.avgFPS, result.avgMS, result.p95MS, result.p99MS, result.oneLowFPS
    ))
    local addonPercent = result.avgMS > 0 and result.addonCPU.total / result.avgMS * 100 or 0
    Addon.Print(string.format(
        "Stutters: %d over 33.3 ms, %d over 50 ms | Addon CPU: %.3f ms/frame (%.1f%%)",
        result.over33, result.over50, result.addonCPU.total, addonPercent
    ))

    if #result.addonCPU.top > 0 then
        local parts = {}
        for index = 1, math.min(5, #result.addonCPU.top) do
            local item = result.addonCPU.top[index]
            parts[#parts + 1] = string.format("%s %.3f", item.name, item.ms)
        end
        Addon.Print("Top addon CPU (ms): " .. table.concat(parts, ", "))
    end

    if previousResult then
        Addon.Print(string.format(
            "Compared with [%s]: FPS %s | avg frame time %s | P99 %s | addon CPU %s",
            previousResult.profile,
            FormatChange(result.avgFPS, previousResult.avgFPS, false),
            FormatChange(result.avgMS, previousResult.avgMS, true),
            FormatChange(result.p99MS, previousResult.p99MS, true),
            FormatChange(result.addonCPU.total, previousResult.addonCPU.total, true)
        ))
    else
        Addon.Print("Baseline saved. Run another benchmark after forcing a different profile for comparison.")
    end
end

local function FinishBenchmark()
    benchmarkFrame:SetScript("OnUpdate", nil)
    if not state or #state.samples == 0 then
        state = nil
        Addon.Print("Benchmark stopped without enough samples.")
        if Addon.RefreshOptions then Addon:RefreshOptions() end
        return
    end

    table.sort(state.samples)
    local count = #state.samples
    local total = state.totalFrameSeconds
    local addonCPU = GatherAddonCPU()
    local result = {
        profile = state.profile,
        duration = total,
        frames = count,
        avgFPS = total > 0 and count / total or 0,
        avgMS = total > 0 and total / count * 1000 or 0,
        p95MS = Percentile(state.samples, 0.95),
        p99MS = Percentile(state.samples, 0.99),
        over33 = state.over33,
        over50 = state.over50,
        addonCPU = addonCPU,
    }
    result.oneLowFPS = result.p99MS > 0 and 1000 / result.p99MS or 0

    previousResult = lastResult
    lastResult = result
    state = nil
    PrintResult(result)
    if Addon.RefreshOptions then Addon:RefreshOptions() end
end

function Addon:StartBenchmark(duration)
    if state then return false, "A benchmark is already running." end
    duration = math.max(5, math.min(60, tonumber(duration) or 15))
    local now = GetTime()
    state = {
        warmupEnd = now + 2,
        finishAt = now + 2 + duration,
        duration = duration,
        profile = self:GetStatusText(),
        samples = {},
        totalFrameSeconds = 0,
        over33 = 0,
        over50 = 0,
    }

    benchmarkFrame:SetScript("OnUpdate", function(_, elapsed)
        local current = GetTime()
        if current < state.warmupEnd then return end
        state.samples[#state.samples + 1] = elapsed
        state.totalFrameSeconds = state.totalFrameSeconds + elapsed
        if elapsed > 0.0333 then state.over33 = state.over33 + 1 end
        if elapsed > 0.0500 then state.over50 = state.over50 + 1 end
        if current >= state.finishAt then FinishBenchmark() end
    end)
    self.Print(string.format("Benchmark warming up for 2s, then sampling for %.0fs. Keep the camera and location comparable.", duration))
    if self.RefreshOptions then self:RefreshOptions() end
    return true
end

function Addon:ClearBenchmarkComparison()
    previousResult = nil
    lastResult = nil
    self.Print("Benchmark comparison cleared.")
    if self.RefreshOptions then self:RefreshOptions() end
end

function Addon:CancelBenchmark(reason)
    if not state then return false end
    benchmarkFrame:SetScript("OnUpdate", nil)
    state = nil
    self.Print(reason or "Benchmark cancelled.")
    if self.RefreshOptions then self:RefreshOptions() end
    return true
end

function Addon:GetBenchmarkStatus()
    if state then
        if GetTime() < state.warmupEnd then
            return "Benchmark: warming up"
        end
        return "Benchmark: sampling current frame times"
    elseif lastResult then
        return string.format("Last: %.1f FPS, P99 %.2f ms — %s", lastResult.avgFPS, lastResult.p99MS, lastResult.profile)
    end
    return "No benchmark recorded yet"
end

function Addon:IsBenchmarkRunning()
    return state ~= nil
end
