--!strict
-- How wide a line of text is, estimated from the fonts' own advance widths (TextService isn't available everywhere
-- this runs, and the harness has no text layout). Used where an icon must sit just left of a centred caption
-- (Widgets: buttons and ribbons centre their icon and text together) and where a widget sizes itself to its text
-- (a toast). The same number on Roblox and in the harness, so screenshots show what Studio shows.
-- Pure Luau: no Roblox APIs.

local TextWidth = {}

-- Advance widths of ASCII 32..126 at 100 px: Fredoka One (titles, buttons, numbers) from its font file, and Inter
-- Bold standing in for Builder Sans Bold (body text), which has nearly the same widths.
-- stylua: ignore
local DISPLAY = {
	25, 27, 43, 75, 48, 84, 75, 21, 38, 38, 50, 53, 24, 43, 24, 53, 61, 41, 61, 61, 59, 53, 56, 56, 58, 56, 24, 24,
	63, 48, 63, 51, 91, 76, 65, 68, 70, 64, 64, 71, 70, 26, 55, 64, 59, 87, 72, 78, 63, 83, 63, 58, 73, 73, 78, 100,
	74, 69, 64, 35, 53, 35, 53, 83, 48, 60, 59, 52, 60, 57, 45, 58, 60, 26, 25, 54, 33, 85, 61, 60, 58, 58, 46, 49,
	45, 61, 64, 79, 57, 60, 59, 38, 22, 38, 65,
}
-- stylua: ignore
local BODY = {
	24, 34, 55, 65, 65, 102, 67, 34, 38, 38, 56, 68, 33, 47, 33, 39, 67, 43, 63, 65, 68, 64, 65, 58, 65, 65, 33, 34,
	68, 68, 68, 56, 102, 75, 66, 74, 72, 61, 59, 75, 75, 28, 58, 72, 57, 93, 76, 77, 65, 78, 66, 65, 67, 73, 75, 104,
	74, 73, 66, 38, 39, 38, 49, 48, 37, 58, 63, 59, 63, 60, 40, 63, 62, 27, 27, 58, 27, 91, 62, 61, 63, 63, 41, 56,
	37, 62, 60, 85, 58, 60, 57, 47, 37, 47, 68,
}
-- Fredoka One's kerning (pairs that move 3 or more at 100 px, from its font file): "AT-19" pulls T 19 left after A.
local KERNING = [==[
"A-10 "C-3 "J-15 "c-5 "e-5 "s-4 'A-10 'C-3 'J-15 'c-5 'e-5 's-4 ,T-11 ,w-5 ,y-5 .T-20 .V-17 .W-9 .v-5 A"-12 A'-12
AC-5 AO-5 AQ-5 AS-3 AT-19 AU-5 AV-15 AW-12 AY-15 Aa-4 Ac-4 Ad-4 Ae-5 Af-9 Ag-4 At-7 Au-4 Av-12 Aw-10 Ay-12 BT-3 Bv-3
Ce-3 Ct-3 Cw-3 Cy-5 D,-5 D.-5 DA-5 DS-4 DT-6 DV-4 DX-4 DY-5 DZ-3 Ec-3 Ee-3 Ev-6 Ew-3 Ey-5 F,-15 F.-15 F;-8 Fa-9 Fc-9
Fd-9 Fe-9 Ff-6 Fg-9 Fm-6 Fn-6 Fo-9 Fp-6 Fq-9 Fr-6 Fs-8 Ft-4 Fu-6 Fv-7 Fw-6 Fx-6 Fy-7 Fz-7 J,-3 KC-7 KG-7 KO-7 KQ-7
Ka-4 Kc-4 Kd-4 Ke-4 Kf-4 Kg-4 Ko-4 Kq-4 Kt-5 Ku-3 Kv-8 Kw-7 Ky-8 L"-12 L'-12 LY-12 Lc-4 Le-4 Lt-12 Lv-13 Lw-10 Ly-12
OA-5 OT-6 OV-4 OX-4 P,-13 PA-8 PT-4 PZ-5 Pc-3 Pe-3 Pz-3 Q"-5 Q'-5 QC-3 QG-3 QO-3 QQ-3 QT-12 QU-4 QV-10 QW-9 QY-9
Qt-5 Qu-3 Qv-4 Qw-4 Qy-4 RT-4 RV-3 RW-3 Ry-3 SA-4 ST-5 SV-3 SW-3 SY-3 Sv-3 Sw-3 Sy-4 T,-14 T.-14 T:-14 T;-14 TA-15
TC-6 TG-6 TJ-15 TO-6 TQ-6 Ta-12 Tc-12 Td-12 Te-12 Tf-8 Tg-12 Tm-12 Tn-12 To-12 Tp-12 Tq-12 Tr-12 Ts-12 Tt-10 Tu-12
Tv-14 Tw-13 Tx-14 Ty-14 Tz-14 U,-4 UA-5 UJ-4 US-3 V,-14 V.-14 V:-5 V;-5 VA-15 VC-4 VG-4 VJ-14 VO-4 VQ-4 Va-10 Vc-10
Vd-10 Ve-10 Vf-5 Vg-10 Vm-4 Vn-4 Vo-10 Vp-4 Vq-10 Vr-4 Vs-7 Vt-5 Vu-4 Vv-5 Vw-4 Vx-5 Vy-5 Vz-5 W,-12 W.-12 W:-5 W;-5
Wa-7 Wc-7 Wd-7 We-7 Wf-4 Wg-7 Wi-3 Wj-3 Wm-5 Wn-5 Wo-7 Wp-6 Wq-7 Wr-5 Ws-7 Wt-5 Wu-5 Wv-5 Ww-5 Wx-6 Wy-5 Wz-7 XC-4
XG-4 XO-4 XQ-4 Xf-5 Xt-5 Xv-6 Xw-6 Xy-6 Y,-15 Y;-8 YA-15 YC-5 YJ-15 Ya-13 Yc-12 Yd-13 Ye-12 Yf-5 Yg-13 Ym-9 Yn-9
Yo-12 Yp-8 Yq-12 Yr-8 Ys-9 Yt-8 Yu-8 Yv-8 Yw-8 Yx-8 Yy-8 Yz-10 Zt-4 Zv-6 Zw-5 Zy-5 aT-11 aV-7 aW-4 aY-7 bT-12 bV-10
bW-7 bY-13 bv-3 bw-3 cT-15 cV-10 cW-7 cY-12 e"-5 e'-5 eY-12 ev-3 ew-3 ey-3 f,-8 f.-8 ff-10 ft-8 gY-9 gj10 hT-14
hV-11 hW-10 hY-12 hv-3 hw-3 kY-11 ka-3 kc-3 kd-3 ke-3 kf-3 kg-3 ko-3 kq-3 kt-3 ku-3 kv-4 kw-3 ky-4 lf-3 lt-4 lv-4
lw-4 ly-5 m"-5 m'-5 mT-14 mV-11 mW-10 mY-11 mv-3 mw-3 my-3 n"-5 n'-5 nT-14 nV-11 nW-10 nY-11 nv-3 nw-3 ny-3 o"-5
o'-5 o,-4 oA-5 oT-12 oV-10 oW-7 oY-13 ov-3 oy-3 p"-5 p'-5 p,-4 pA-5 pT-12 pV-10 pW-7 pv-3 py-3 qY-8 qj12 r,-10 r.-10
rA-10 rJ-12 rT-10 rV-4 rY-6 rZ-4 ra-3 rc-3 rd-3 re-3 rg-3 ro-3 rq-3 s"-4 s'-4 sT-12 sY-8 sv-4 sw-3 sy-4 tY-6 tt-10
uT-12 uV-7 uW-6 uY-6 v,-10 v.-10 vY-6 va-3 vc-3 vd-3 ve-3 vg-3 vo-3 vq-3 w,-8 w.-8 wT-11 wV-4 wW-5 wX-6 wY-8 y,-7
yA-8 yJ-9 yT-14 yV-4 yX-6 yY-10 yZ-8 yc-3 ye-3 zT-10 zV-7 zW-8 zY-10 zc-3 ze-3 zy-3
]==]
local KERN: { [string]: number } = {}
for pair, amount in string.gmatch(KERNING, "(%S%S)(%-?%d+)") do
	KERN[pair] = tonumber(amount) :: number
end

local MIDDOT = 0xB7 -- "·", the separator in "Quests · 2 to claim"
local OTHER = 62 -- anything else (accents, the Robux glyph): about an average letter

export type Face = "display" | "body"

-- The width in px of `text` (one line, no rich text) in `face` at `size` px.
function TextWidth.measure(text: string, size: number, face: Face?): number
	local display = face ~= "body"
	local widths = if display then DISPLAY else BODY
	local total = 0
	local last = 0
	for _, code in utf8.codes(text) do
		if code >= 32 and code <= 126 then
			total += widths[code - 31]
			if display and last ~= 0 then
				total += KERN[string.char(last, code)] or 0
			end
			last = code
		else
			total += if code == MIDDOT then 24 else OTHER
			last = 0
		end
	end
	return total * size / 100
end

return TextWidth
