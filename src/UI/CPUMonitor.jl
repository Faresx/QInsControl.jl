function CPUMonitor()
    cpuinfo = remotecall_fetch(workers()[1]) do
        Dict(
            :running => CPU.running[],
            :taskfailed => istaskfailed(CPU.processtask[]),
            :fast => CPU.fast[],
            :resourcemanager => CPU.resourcemanager[],
            :isconnected => Dict(addr => QInsControlCore.isconnected(instr) for (addr, instr) in CPU.instrs),
            :controllers => CPU.controllers,
            :taskhandlers => CPU.taskhandlers,
            :tasksfailed => Dict(addr => istaskfailed(task) for (addr, task) in CPU.tasks)
        )
    end
    SeparatorTextColored(MORESTYLE.Colors.HighlightText, mlstr("Processor"))
    CImGui.Indent()
    if cpuinfo[:running]
        igBeginDisabled(SYNCSTATES[Int(IsDAQTaskRunning)])
        ToggleButton(mlstr("Running"), Ref(true)) && remotecall_wait(() -> stop!(CPU), workers()[1])
        igEndDisabled()
        CImGui.SameLine()
        ColoredButton(
            mlstr(cpuinfo[:taskfailed] ? "Failed" : "Well");
            colbt=cpuinfo[:taskfailed] ? MORESTYLE.Colors.LogError : MORESTYLE.Colors.LogInfo,
            colbth=cpuinfo[:taskfailed] ? MORESTYLE.Colors.LogError : MORESTYLE.Colors.LogInfo,
            colbta=cpuinfo[:taskfailed] ? MORESTYLE.Colors.LogError : MORESTYLE.Colors.LogInfo
        )
        CImGui.SameLine()
        if CImGui.Checkbox(mlstr(cpuinfo[:fast] ? "Fast Mode" : "Slow Mode"), Ref(cpuinfo[:fast]))
            remotecall_wait((isfast) -> CPU.fast[] = !isfast, workers()[1], cpuinfo[:fast])
        end
    else
        ToggleButton(mlstr("Stopped"), Ref(false)) && remotecall_wait(() -> start!(CPU), workers()[1])
    end
    CImGui.Unindent()
    CImGui.Spacing()
    SeparatorTextColored(MORESTYLE.Colors.HighlightText, mlstr("Controllers"))
    CImGui.Indent()
    CImGui.Button(
        stcstr(MORESTYLE.Icons.InstrumentsManualRef, " ", mlstr("Reconnect"))
    ) && remotecall_wait(() -> reconnect!(CPU), workers()[1])
    if isempty(cpuinfo[:controllers])
        CImGui.TextDisabled(stcstr("(", mlstr("Null"), ")"))
    else
        instrtocontrollers = Dict()
        for ct in cpuinfo[:controllers]
            haskey(instrtocontrollers, ct.instrnm) || push!(instrtocontrollers, ct.instrnm => Dict())
            haskey(instrtocontrollers[ct.instrnm], ct.addr) || push!(instrtocontrollers[ct.instrnm], ct.addr => [])
            push!(instrtocontrollers[ct.instrnm][ct.addr], ct)
        end
        for (ins, inses) in instrtocontrollers
            CImGui.TextColored(MORESTYLE.Colors.HighlightText, stcstr(mlstr("Instrument"), " : ", ins))
            CImGui.Indent()
            for (addr, cts) in inses
                CImGui.Text(addr)
                CImGui.SameLine()
                CImGui.TextColored(
                    cpuinfo[:isconnected][addr] ? MORESTYLE.Colors.LogInfo : MORESTYLE.Colors.LogError,
                    mlstr(cpuinfo[:isconnected][addr] ? "Connected" : "Unconnected")
                )
                CImGui.Text(stcstr(mlstr("Status"), "："))
                CImGui.SameLine()
                CImGui.TextColored(
                    cpuinfo[:taskhandlers][addr] ? MORESTYLE.Colors.LogInfo : MORESTYLE.Colors.LogError,
                    mlstr(cpuinfo[:taskhandlers][addr] ? "Running" : "Stopped")
                )
                CImGui.SameLine()
                CImGui.TextColored(
                    cpuinfo[:tasksfailed][addr] ? MORESTYLE.Colors.LogError : MORESTYLE.Colors.LogInfo,
                    mlstr(cpuinfo[:tasksfailed][addr] ? "Failed" : "Well")
                )
                CImGui.Indent()
                for ct in cts
                    idx = findfirst(==(ct), cpuinfo[:controllers])
                    CImGui.Text(stcstr(mlstr("Controller"), " ", idx))
                    @cstatic cols::Cint = 2 begin
                        CImGui.PushItemWidth(6CImGui.GetFontSize())
                        @c CImGui.DragInt(mlstr("Buffer"), &cols, 1, 1, 64, "%d", CImGui.ImGuiSliderFlags_AlwaysClamp)
                        CImGui.PopItemWidth()
                        CImGui.BeginTable(stcstr("Controller", idx), cols, CImGui.ImGuiTableFlags_Borders)
                        for idxes in Iterators.partition(eachindex(ct.databuf), cols)
                            CImGui.TableNextRow()
                            for i in idxes
                                CImGui.TableSetColumnIndex((i - 1) % cols)
                                CImGui.Text(ct.databuf[i])
                                ct.available[i] || CImGui.TableSetBgColor(
                                    CImGui.ImGuiTableBgTarget_CellBg,
                                    CImGui.ColorConvertFloat4ToU32(MORESTYLE.Colors.LogError)
                                )
                            end
                        end
                        CImGui.EndTable()
                    end
                end
                CImGui.Unindent()
            end
            CImGui.Unindent()
        end
    end
    CImGui.Unindent()
end