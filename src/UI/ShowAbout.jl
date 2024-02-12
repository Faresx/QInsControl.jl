function ShowAbout()
    if CImGui.BeginPopupModal(mlstr("About"), C_NULL, CImGui.ImGuiWindowFlags_AlwaysAutoResize)
        ftsz = CImGui.GetFontSize()
        ww = CImGui.GetWindowWidth()
        # CImGui.SameLine(ww / 3)
        CImGui.SetCursorPos(ww / 3, CImGui.GetCursorPosY())
        CImGui.Image(Ptr{Cvoid}(ICONID), (ww / 3, ww / 3))
        CImGui.PushFont(PLOTFONT)
        # CImGui.SameLine()
        CImGui.SetCursorPos(CImGui.GetCursorPos() .+ ((ww - CImGui.CalcTextSize("QInsControl").x) / 2, ftsz))
        CImGui.TextColored(MORESTYLE.Colors.HighlightText, "QInsControl\n")
        CImGui.PopFont()
        CImGui.Text(stcstr(mlstr("version"), " : 0.1.0"))
        CImGui.Text(stcstr(mlstr("author"), " : XST\n"))
        CImGui.Text(stcstr(mlstr("license"), " : MPL-2.0 License\n"))
        CImGui.Text(stcstr(mlstr("github"), " : "))
        CImGui.SameLine()
        CImGui.TextColored(MORESTYLE.Colors.LogInfo, "https://github.com/FaresX/QInsControl.jl")
        CImGui.IsItemClicked() && Threads.@spawn Base.run(`explorer https://github.com/FaresX/QInsControl.jl`)
        CImGui.Text("\n")
        global JLVERINFO
        CImGui.Text(JLVERINFO)
        CImGui.Text("\n")
        CImGui.Button(stcstr(mlstr("Confirm"), "##ShowAbout"), (-1, 0)) && CImGui.CloseCurrentPopup()
        CImGui.EndPopup()
    end
end
