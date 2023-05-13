mutable struct InstrQuantity
    enable::Bool
    name::String
    alias::String
    step::String
    stop::String
    delay::Cfloat
    set::String
    optvalues::Vector{String}
    optedvalueidx::Cint
    read::String
    utype::String
    uindex::Int
    type::Symbol
    help::String
    isautorefresh::Bool
    issweeping::Bool
end
InstrQuantity() = InstrQuantity(true, "", "", "", "", Cfloat(0.1), "", [""], 1, "", "", 1, :set, "", false, false)
function InstrQuantity(name, qtcf::QuantityConf)
    InstrQuantity(
        qtcf.enable,
        name,
        qtcf.alias,
        "",
        "",
        Cfloat(0.1),
        "",
        qtcf.optvalues,
        1,
        "",
        qtcf.U,
        1,
        Symbol(qtcf.type),
        qtcf.help,
        false,
        false
    )
end

mutable struct InstrBuffer
    instrnm::String
    quantities::OrderedDict{String,InstrQuantity}
    isautorefresh::Bool
end
InstrBuffer() = InstrBuffer("", OrderedDict(), false)

function InstrBuffer(instrnm)
    haskey(insconf, instrnm) || @error "[$(now())]\n不支持的仪器!!!" instrument = instrnm
    sweepqts = [qt for qt in keys(insconf[instrnm].quantities) if insconf[instrnm].quantities[qt].type == "sweep"]
    setqts = [qt for qt in keys(insconf[instrnm].quantities) if insconf[instrnm].quantities[qt].type == "set"]
    readqts = [qt for qt in keys(insconf[instrnm].quantities) if insconf[instrnm].quantities[qt].type == "read"]
    quantities = [sweepqts; setqts; readqts]
    instrqts = OrderedDict()
    for qt in quantities
        enable = insconf[instrnm].quantities[qt].enable
        alias = insconf[instrnm].quantities[qt].alias
        optvalues = insconf[instrnm].quantities[qt].optvalues
        utype = insconf[instrnm].quantities[qt].U
        type = Symbol(insconf[instrnm].quantities[qt].type)
        help = replace(insconf[instrnm].quantities[qt].help, "\\\n" => "")
        push!(instrqts, qt => InstrQuantity(enable, qt, alias, "", "", Cfloat(0.1), "", optvalues, 1, "", utype, 1, type, help, false, false))
    end
    InstrBuffer(instrnm, instrqts, false)
end

mutable struct InstrBufferViewer
    instrnm::String
    addr::String
    inputcmd::String
    readstr::String
    p_open::Bool
    insbuf::InstrBuffer
end
InstrBufferViewer(instrnm, addr) = InstrBufferViewer(instrnm, addr, "*IDN?", "", false, InstrBuffer(instrnm))
InstrBufferViewer() = InstrBufferViewer("", "", "*IDN?", "", false, InstrBuffer())

# const instrcontrollers::Dict{String,Dict{String,Controller}} = Dict()
const instrbufferviewers::Dict{String,Dict{String,InstrBufferViewer}} = Dict()
refreshrate::Cfloat = 6 #仪器状态刷新率

let
    # window_ids::Dict{Tuple{String,String},String} = Dict()
    global function edit(ibv::InstrBufferViewer)
        # CImGui.SetNextWindowPos((600, 100), CImGui.ImGuiCond_Once)
        # CImGui.SetNextWindowSize((600, 400), CImGui.ImGuiCond_Once)
        ins, addr = ibv.instrnm, ibv.addr
        if @c CImGui.Begin(string(insconf[ins].conf.icon, "  ", ins, " --- ", addr), &ibv.p_open)
            @c testcmd(ins, addr, &ibv.inputcmd, &ibv.readstr)
            edit(ibv.insbuf, addr)
            if !CImGui.IsAnyItemHovered() && CImGui.IsWindowHovered(CImGui.ImGuiHoveredFlags_ChildWindows)
                CImGui.OpenPopupOnItemClick("rightclick")
            end
            if CImGui.BeginPopup("rightclick")
                global refreshrate
                if CImGui.MenuItem(
                    morestyle.Icons.InstrumentsManualRef * " 手动刷新",
                    "F5",
                    false,
                    !syncstates[Int(isdaqtask_running)]
                )
                    ibv.insbuf.isautorefresh = true
                    manualrefresh()
                end
                CImGui.Text(morestyle.Icons.InstrumentsAutoRef * " 自动刷新")
                CImGui.SameLine()
                isautoref = syncstates[Int(isautorefresh)]
                @c CImGui.Checkbox("##自动刷新", &isautoref)
                syncstates[Int(isautorefresh)] = isautoref
                ibv.insbuf.isautorefresh = syncstates[Int(isautorefresh)]
                if isautoref
                    CImGui.SameLine()
                    CImGui.Text(" ")
                    CImGui.SameLine()
                    CImGui.PushItemWidth(CImGui.GetFontSize() * 2)
                    @c CImGui.DragFloat("##自动刷新", &refreshrate, 0.1, 0.1, 60, "%.1f", CImGui.ImGuiSliderFlags_AlwaysClamp)
                    # remotecall_wait((x) -> (global refreshrate = x), workers()[1], refreshrate)
                    CImGui.PopItemWidth()
                end
                CImGui.EndPopup()
            end
            CImGui.IsKeyReleased(294) && manualrefresh()
        end
        CImGui.End()
    end
end

let
    firsttime::Bool = true
    selectedins::String = ""
    selectedaddr::String = ""
    inputcmd::String = "*IDN?"
    readstr::String = ""
    default_insbufs = Dict{String,InstrBuffer}()
    global function ShowInstrBuffer(p_open::Ref)
        # CImGui.SetNextWindowPos((600, 100), CImGui.ImGuiCond_Once)
        # CImGui.SetNextWindowSize((1000, 800), CImGui.ImGuiCond_Once)
        if CImGui.Begin(morestyle.Icons.InstrumentsOverview * "  仪器设置和状态", p_open)
            CImGui.Columns(2)
            firsttime && (CImGui.SetColumnOffset(1, CImGui.GetWindowWidth() * 0.25); firsttime = false)
            CImGui.BeginChild("仪器列表")
            CImGui.Selectable(morestyle.Icons.InstrumentsOverview * " 总览", selectedins == "") && (selectedins = "")
            for ins in keys(instrbufferviewers)
                CImGui.Selectable(insconf[ins].conf.icon * " " * ins, selectedins == ins) && (selectedins = ins)
                CImGui.SameLine()
                CImGui.TextDisabled("($(length(instrbufferviewers[ins])))")
            end
            CImGui.EndChild()
            if CImGui.BeginPopupContextItem()
                global refreshrate
                if CImGui.MenuItem(
                    morestyle.Icons.InstrumentsManualRef * " 手动刷新",
                    "F5",
                    false,
                    !syncstates[Int(isdaqtask_running)]
                )
                    manualrefresh()
                end
                CImGui.Text(morestyle.Icons.InstrumentsAutoRef * " 自动刷新")
                CImGui.SameLine()
                isautoref = syncstates[Int(isautorefresh)]
                @c CImGui.Checkbox("##自动刷新", &isautoref)
                syncstates[Int(isautorefresh)] = isautoref
                if isautoref
                    CImGui.SameLine()
                    CImGui.Text(" ")
                    CImGui.SameLine()
                    CImGui.PushItemWidth(CImGui.GetFontSize() * 2)
                    @c CImGui.DragFloat("##自动刷新", &refreshrate, 0.1, 0.1, 60, "%.1f", CImGui.ImGuiSliderFlags_AlwaysClamp)
                    # remotecall_wait((x) -> (global refreshrate = x), workers()[1], refreshrate)
                    CImGui.PopItemWidth()
                end
                CImGui.EndPopup()
            end
            CImGui.IsKeyReleased(294) && manualrefresh()
            CImGui.NextColumn()
            CImGui.BeginChild("设置选项")
            haskey(instrbufferviewers, selectedins) || (selectedins = "")
            if selectedins == ""
                for ins in keys(instrbufferviewers)
                    CImGui.TextColored(morestyle.Colors.HighlightText, string(ins, "："))
                    for (addr, ibv) in instrbufferviewers[ins]
                        CImGui.Text(string("\t\t", addr, "\t\t"))
                        CImGui.SameLine()
                        @c CImGui.Checkbox("##是否自动刷新$addr", &ibv.insbuf.isautorefresh)
                    end
                    CImGui.Separator()
                end
            else
                showinslist::Set = @trypass keys(instrbufferviewers[selectedins]) Set{String}()
                CImGui.PushItemWidth(-CImGui.GetFontSize() * 2.5)
                @c ComBoS("地址", &selectedaddr, showinslist)
                CImGui.PopItemWidth()
                CImGui.Separator()
                @c testcmd(selectedins, selectedaddr, &inputcmd, &readstr)

                selectedaddr = haskey(instrbufferviewers[selectedins], selectedaddr) ? selectedaddr : ""
                haskey(default_insbufs, selectedins) || push!(default_insbufs, selectedins => InstrBuffer(selectedins))
                insbuf = selectedaddr == "" ? default_insbufs[selectedins] : instrbufferviewers[selectedins][selectedaddr].insbuf
                edit(insbuf, selectedaddr)
            end
            CImGui.EndChild()
        end
        CImGui.End()
    end
end #let    

function testcmd(ins, addr, inputcmd::Ref{String}, readstr::Ref{String})
    if CImGui.CollapsingHeader("\t指令测试")
        y = (1 + length(findall("\n", inputcmd[]))) * CImGui.GetTextLineHeight() + 2unsafe_load(imguistyle.FramePadding.y)
        InputTextMultilineRSZ("##输入命令", inputcmd, (Float32(-1), y))
        if CImGui.BeginPopupContextItem()
            CImGui.MenuItem("清空") && (inputcmd[] = "")
            CImGui.EndPopup()
        end
        TextRect(string(readstr[], "\n "))
        CImGui.BeginChild("对齐按钮", (Float32(0), CImGui.GetFrameHeightWithSpacing()))
        CImGui.PushStyleVar(CImGui.ImGuiStyleVar_FrameRounding, 12)
        CImGui.Columns(3, C_NULL, false)
        if CImGui.Button(morestyle.Icons.WriteBlock * "  Write", (-1, 0))
            if addr != ""
                remotecall_wait(workers()[1], ins, addr, inputcmd[]) do ins, addr, inputcmd
                    ct = Controller(ins, addr)
                    try
                        login!(CPU, ct)
                        ct(write, CPU, inputcmd, Val(:write))
                        logout!(CPU, ct)
                    catch e
                        @error "[$(now())]\n仪器通信故障！！！" exception=e
                        logout!(CPU, ct)
                    end
                end
            end
        end
        CImGui.NextColumn()
        if CImGui.Button(morestyle.Icons.QueryBlock * "  Query", (-1, 0))
            if addr != ""
                fetchdata = remotecall_fetch(workers()[1], ins, addr, inputcmd[]) do ins, addr, inputcmd
                    ct = Controller(ins, addr)
                    try
                        login!(CPU, ct)
                        readstr = ct(query, CPU, inputcmd, Val(:query))
                        logout!(CPU, ct)
                        return readstr
                    catch e
                        @error "[$(now())]\n仪器通信故障！！！" exception=e
                        logout!(CPU, ct)
                    end
                end
                isnothing(fetchdata) || (readstr[] = fetchdata)
            end
        end
        CImGui.NextColumn()
        if CImGui.Button(morestyle.Icons.ReadBlock * "  Read", (-1, 0))
            if addr != ""
                fetchdata = remotecall_fetch(workers()[1], ins, addr) do ins, addr
                    ct = Controller(ins, addr)
                    try
                        login!(CPU, ct)
                        readstr = ct(read, CPU, Val(:read))
                        logout!(CPU, ct)
                        return readstr
                    catch e
                        @error "[$(now())]\n仪器通信故障！！！" exception=e
                        logout!(CPU, ct)
                    end
                end 
                isnothing(fetchdata) || (readstr[] = fetchdata)
            end
        end
        CImGui.NextColumn()
        CImGui.PopStyleVar()
        CImGui.EndChild()
        CImGui.Separator()
    end
end

function edit(insbuf::InstrBuffer, addr)
    CImGui.PushID(insbuf.instrnm)
    CImGui.PushID(addr)
    CImGui.BeginChild("InstrBuffer")
    CImGui.Columns(conf.InsBuf.showcol, C_NULL, false)
    for (i, qt) in enumerate(values(insbuf.quantities))
        qt.enable || continue
        CImGui.PushID(qt.name)
        edit(qt, insbuf.instrnm, addr)
        CImGui.PopID()
        CImGui.NextColumn()
        CImGui.Indent()
        if CImGui.BeginDragDropSource(0)
            @c CImGui.SetDragDropPayload("Swap DAQTask", &i, sizeof(Cint))
            CImGui.EndDragDropSource()
        end
        if CImGui.BeginDragDropTarget()
            payload = CImGui.AcceptDragDropPayload("Swap DAQTask")
            if payload != C_NULL && unsafe_load(payload).DataSize == sizeof(Cint)
                payload_i = unsafe_load(Ptr{Cint}(unsafe_load(payload).Data))
                if i != payload_i
                    key_i = idxkey(insbuf.quantities, i)
                    key_payload_i = idxkey(insbuf.quantities, payload_i)
                    swapvalue!(insbuf.quantities, key_i, key_payload_i)
                end
            end
            CImGui.EndDragDropTarget()
        end
        CImGui.Unindent()
    end
    CImGui.EndChild()
    CImGui.PopID()
    CImGui.PopID()
end

edit(qt::InstrQuantity, instrnm::String, addr::String) = edit(qt, instrnm, addr, Val(qt.type))

let
    stbtsz::Float32 = 0
    Us = []
    U = ""
    val::String = ""
    content::String = ""
    global function edit(qt::InstrQuantity, instrnm::String, addr::String, ::Val{:sweep})
        Us = conf.U[qt.utype]
        U = isempty(Us) ? "" : Us[qt.uindex]
        U == "" || (Uchange::Float64 = Us[1] isa Unitful.FreeUnits ? ustrip(Us[1], 1U) : 1.0)
        val = U == "" ? qt.read : @trypass string(parse(Float64, qt.read) / Uchange) qt.read
        content = string(
            qt.alias,
            "\n步长：", qt.step, " ", U,
            "\n终点：", qt.stop, " ", U,
            "\n延迟：", qt.delay, " s\n",
            val, " ", U
        ) |> centermultiline
        content = string(content, "###for rename")
        CImGui.PushStyleColor(
            CImGui.ImGuiCol_Button,
            qt.isautorefresh || qt.issweeping ? morestyle.Colors.DAQTaskRunning : CImGui.c_get(imguistyle.Colors, CImGui.ImGuiCol_Button)
        )
        if CImGui.Button(content, (-1, 0))
            if addr != ""
                fetchdata = refresh_qt(instrnm, addr, qt.name)
                isnothing(fetchdata) || (qt.read = fetchdata)
            end
        end
        CImGui.PopStyleColor()
        if conf.InsBuf.showhelp && CImGui.IsItemHovered() && qt.help != ""
            ItemTooltip(qt.help)
        end
        if CImGui.BeginPopupContextItem()
            @c InputTextWithHintRSZ("##步长", "步长", &qt.step)
            @c InputTextWithHintRSZ("##终点", "终点", &qt.stop)
            @c CImGui.DragFloat("##延迟", &qt.delay, 1.0, 0.05, 60, "%.3f", CImGui.ImGuiSliderFlags_AlwaysClamp)
            if qt.issweeping
                if CImGui.Button(" 结束 ", (-1, 0))
                    qt.issweeping = false
                end
            else
                if CImGui.Button(" 开始 ", (-1, 0))
                    if addr != ""
                        start = remotecall_fetch(workers()[1], instrnm, addr) do instrnm, addr
                            ct = Controller(instrnm, addr)
                            try
                                getfunc = Symbol(instrnm, :_, qt.name, :_get) |> eval
                                login!(CPU, ct)
                                readstr = ct(getfunc, CPU, Val(:read))
                                logout!(CPU, ct)
                                return parse(Float64, readstr)
                            catch e
                                @error "[$(now())]\nstart获取错误！！！" instrument = string(instrnm, "-", addr) exception=e
                                logout!(CPU, ct)
                            end
                        end
                        step = @trypasse eval(Meta.parse(qt.step)) * Uchange begin
                            @error "[$(now())]\nstep解析错误！！！" step = qt.step
                        end
                        stop = @trypasse eval(Meta.parse(qt.stop)) * Uchange begin
                        @error "[$(now())]\nstop解析错误！！！" stop = qt.stop
                        end
                        if !(isnothing(start) || isnothing(step) || isnothing(stop))
                            sweepsteps = ceil(Int, abs((start - stop) / step))
                            sweepsteps = sweepsteps == 1 ? 2 : sweepsteps
                            sweeptask = @async begin
                                qt.issweeping = true
                                ct = Controller(instrnm, addr)
                                try
                                    remotecall_wait(workers()[1], ct) do ct
                                        global sweepct = ct
                                        login!(CPU, ct)
                                    end
                                    for i in range(start, stop, length=sweepsteps)
                                        qt.issweeping || break
                                        sleep(qt.delay)
                                        qt.read = remotecall_fetch(workers()[1], i) do i
                                            setfunc = Symbol(instrnm, :_, qt.name, :_set) |> eval
                                            getfunc = Symbol(instrnm, :_, qt.name, :_get) |> eval
                                            sweepct(setfunc, CPU, string(i), Val(:write))
                                            return sweepct(getfunc, CPU, Val(:read))
                                        end
                                    end
                                catch e
                                    @error "[$(now())]\n仪器通信故障！！！" exception=e
                                finally
                                    remotecall_wait(() -> logout!(CPU, sweepct), workers()[1])
                                end
                                qt.issweeping = false
                            end
                            errormonitor(sweeptask)
                        end
                    end
                end
            end
            CImGui.Text("单位 ")
            CImGui.SameLine()
            CImGui.PushItemWidth(6CImGui.GetFontSize())
            @c ShowUnit("##insbuf", qt.utype, &qt.uindex)
            CImGui.PopItemWidth()
            CImGui.SameLine(0, 2CImGui.GetFontSize())
            @c CImGui.Checkbox("刷新", &qt.isautorefresh)
            CImGui.EndPopup()
        end
    end
end #let

let
    triggerset::Bool = false
    Us = []
    U = ""
    val::String = ""
    content::String = ""
    global function edit(qt::InstrQuantity, instrnm::String, addr::String, ::Val{:set})
        Us = conf.U[qt.utype]
        U = isempty(Us) ? "" : Us[qt.uindex]
        U == "" || (Uchange::Float64 = Us[1] isa Unitful.FreeUnits ? ustrip(Us[1], 1U) : 1.0)
        val = U == "" ? qt.read : @trypass string(parse(Float64, qt.read) / Uchange) qt.read
        content = string(qt.alias, "\n \n设置值：", qt.set, " ", U, "\n \n", val, " ", U) |> centermultiline
        content = string(content, "###for rename")
        CImGui.PushStyleColor(
            CImGui.ImGuiCol_Button,
            qt.isautorefresh ? morestyle.Colors.DAQTaskRunning : CImGui.c_get(imguistyle.Colors, CImGui.ImGuiCol_Button)
        )
        if CImGui.Button(content, (-1, 0))
            if addr != ""
                fetchdata = refresh_qt(instrnm, addr, qt.name)
                isnothing(fetchdata) || (qt.read = fetchdata)
            end
        end
        CImGui.PopStyleColor()
        if conf.InsBuf.showhelp && CImGui.IsItemHovered() && qt.help != ""
            ItemTooltip(qt.help)
        end
        if CImGui.BeginPopupContextItem()
            @c InputTextWithHintRSZ("##设置", "设置值", &qt.set)
            if CImGui.Button(" 确认 ", (-1, 0)) || triggerset
                triggerset = false
                if addr != ""
                    sv = U == "" ? qt.set : @trypasse string(float(eval(Meta.parse(qt.set)) * Uchange)) qt.set
                    triggerset && (sv = qt.optvalues[qt.optedvalueidx])
                    fetchdata = remotecall_fetch(workers()[1], instrnm, addr, sv) do instrnm, addr, sv
                        ct = Controller(instrnm, addr)
                        try
                            setfunc = Symbol(instrnm, :_, qt.name, :_set) |> eval
                            getfunc = Symbol(instrnm, :_, qt.name, :_get) |> eval
                            login!(CPU, ct)
                            ct(setfunc, CPU, sv, Val(:write))
                            readstr = ct(getfunc, CPU, Val(:read))
                            logout!(CPU, ct)
                            return readstr
                        catch e
                            @error "[$(now())]\n仪器通信故障！！！" exception=e
                            logout!(CPU, ct)
                        end
                    end 
                    isnothing(fetchdata) || (qt.read = fetchdata)
                end
            end
            for (i, optv) in enumerate(qt.optvalues)
                optv == "" && continue
                @c(CImGui.RadioButton(optv, &qt.optedvalueidx, i)) && (qt.set = optv; triggerset = true)
                i % 2 == 1 && CImGui.SameLine(0, 2CImGui.GetFontSize())
            end
            CImGui.Text("单位 ")
            CImGui.SameLine()
            CImGui.PushItemWidth(6CImGui.GetFontSize())
            @c ShowUnit("##insbuf", qt.utype, &qt.uindex)
            CImGui.PopItemWidth()
            CImGui.SameLine(0, 2CImGui.GetFontSize())
            @c CImGui.Checkbox("刷新", &qt.isautorefresh)
            CImGui.EndPopup()
        end
    end
end

let
    refbtsz::Float32 = 0
    Us = []
    U = ""
    val::String = ""
    content::String = ""
    global function edit(qt::InstrQuantity, instrnm, addr, ::Val{:read})
        Us = conf.U[qt.utype]
        U = isempty(Us) ? "" : Us[qt.uindex]
        U == "" || (Uchange::Float64 = Us[1] isa Unitful.FreeUnits ? ustrip(Us[1], 1U) : 1.0)
        val = U == "" ? qt.read : @trypass string(parse(Float64, qt.read) / Uchange) qt.read
        content = string(qt.alias, "\n \n \n", val, " ", U, "\n ") |> centermultiline
        CImGui.PushStyleColor(
            CImGui.ImGuiCol_Button,
            qt.isautorefresh ? morestyle.Colors.DAQTaskRunning : CImGui.c_get(imguistyle.Colors, CImGui.ImGuiCol_Button)
        )
        if CImGui.Button(content, (-1, 0))
            if addr != ""
                fetchdata = refresh_qt(instrnm, addr, qt.name)
                isnothing(fetchdata) || (qt.read = fetchdata)
            end
        end
        CImGui.PopStyleColor()
        if conf.InsBuf.showhelp && CImGui.IsItemHovered() && qt.help != ""
            ItemTooltip(qt.help)
        end
        if CImGui.BeginPopupContextItem()
            CImGui.Text("单位 ")
            CImGui.SameLine()
            CImGui.PushItemWidth(6CImGui.GetFontSize())
            @c ShowUnit("##insbuf", qt.utype, &qt.uindex)
            CImGui.PopItemWidth()
            CImGui.SameLine(0, 2CImGui.GetFontSize())
            @c CImGui.Checkbox("刷新", &qt.isautorefresh)
            CImGui.EndPopup()
        end
    end
end

function view(instrbufferviewers_local)
    for ins in keys(instrbufferviewers_local)
        ins == "Others" && continue
        for (addr, ibv) in instrbufferviewers_local[ins]
            CImGui.TextColored(morestyle.Colors.HighlightText, string(ins, "：", addr))
            CImGui.PushID(addr)
            view(ibv.insbuf)
            CImGui.PopID()
        end
    end
end

function view(insbuf::InstrBuffer)
    y = ceil(Int, length(insbuf.quantities) / conf.InsBuf.showcol) * 2CImGui.GetFrameHeight()
    CImGui.BeginChild("view insbuf", (Float32(0), y))
    CImGui.Columns(conf.InsBuf.showcol, C_NULL, false)
    CImGui.PushID(insbuf.instrnm)
    for (name, qt) in insbuf.quantities
        qt.enable || continue
        CImGui.PushID(name)
        view(qt)
        CImGui.NextColumn()
        CImGui.PopID()
    end
    CImGui.PopID()
    CImGui.EndChild()
end

let
    Us = []
    U = ""
    val::String = ""
    content::String = ""
    global function view(qt::InstrQuantity)
        Us = conf.U[qt.utype]
        U = isempty(Us) ? "" : Us[qt.uindex]
        U == "" || (Uchange::Float64 = Us[1] isa Unitful.FreeUnits ? ustrip(Us[1], 1U) : 1.0)
        val = U == "" ? qt.read : @trypass string(parse(Float64, qt.read) / Uchange) qt.read
        content = string(qt.alias, "\n", val, " ", U) |> centermultiline
        if CImGui.Button(content, (-1, 0))
            qt.uindex = (qt.uindex + 1) % length(Us)
            qt.uindex == 0 && (qt.uindex = length(Us))
        end
    end
end

function refresh_qt(instrnm, addr, qtnm)
    remotecall_fetch(workers()[1], instrnm, addr) do instrnm, addr
        ct = Controller(instrnm, addr)
        try
            getfunc = Symbol(instrnm, :_, qtnm, :_get) |> eval
            login!(CPU, ct)
            readstr = ct(getfunc, CPU, Val(:read))
            logout!(CPU, ct)
            return readstr
        catch e
            @error "[$(now())]\n仪器通信故障！！！" exception=e
            logout!(CPU, ct)
        end
    end
end

function log_instrbufferviewers()
    manualrefresh()
    push!(cfgbuf, "instrbufferviewers/[$(now())]" => deepcopy(instrbufferviewers))
end

function refresh_fetch_ibvs(ibvs_local; log=false)
    remotecall_fetch(workers()[1], ibvs_local, log) do ibvs_local, log
        @sync for ins in keys(ibvs_local)
            ins == "Others" && continue
            for (addr, ibv) in ibvs_local[ins]
                @async begin
                    if ibv.insbuf.isautorefresh || log
                        ct = Controller(ins, addr)
                        try
                            login!(CPU, ct)
                            for (qtnm, qt) in ibv.insbuf.quantities
                                if qt.isautorefresh || log
                                    getfunc = Symbol(ins, :_, qtnm, :_get) |> eval
                                    qt.read = ct(getfunc, CPU, Val(:read))
                                end
                            end
                            logout!(CPU, ct)
                        catch e
                            @error "[$(now())]\n仪器通信故障！！！" exception=e
                            logout!(CPU, ct)
                        end
                    end
                end
            end
        end
        return ibvs_local
    end
end

function manualrefresh()
    ibvs_remote = refresh_fetch_ibvs(instrbufferviewers; log = true)
    for ins in keys(instrbufferviewers)
        ins == "Others" && continue
        for (addr, ibv) in instrbufferviewers[ins]
            for (qtnm, qt) in ibv.insbuf.quantities
                qt.read = ibvs_remote[ins][addr].insbuf.quantities[qtnm].read
            end
        end
    end
end

function autorefresh()
    errormonitor(
        @async while true
            i_sleep = 0
            while i_sleep < refreshrate
                sleep(0.1)
                i_sleep += 0.1
            end
            if syncstates[Int(isautorefresh)]
                ibvs_remote = refresh_fetch_ibvs(instrbufferviewers)
                for ins in keys(instrbufferviewers)
                    ins == "Others" && continue
                    for (addr, ibv) in instrbufferviewers[ins]
                        if ibv.insbuf.isautorefresh
                            for (qtnm, qt) in ibv.insbuf.quantities
                                if qt.isautorefresh
                                    qt.read = ibvs_remote[ins][addr].insbuf.quantities[qtnm].read
                                end
                            end
                        end
                    end
                end
            end
        end
    )
end