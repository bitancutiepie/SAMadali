@{
    # =====================================================================
    #  IT 311 FINAL LAB - CENTRAL EXAM-DAY CONFIGURATION
    #  Edit ONLY this file on exam day. Every other script reads it.
    # =====================================================================

    # ---- Task Area 01: Virtual Machine --------------------------------
    # Exact VM name from the instruction sheet. Spelling counts.
    VMName               = 'Lab_Exam_VM'

    # Memory in MB. 1 GB = 1024 MB. Rubric minimum: 2048 MB.
    # Recommended: 4096 MB.
    RAM_MB               = 4096

    # Dynamically allocated VDI size in GB. Rubric minimum: 20 GB.
    # Recommended: 30 GB.
    Disk_GB              = 30

    # nat | bridged | hostonly | intnet
    NetMode              = 'bridged'

    # Leave blank to auto-detect the active physical host NIC.
    # Set an exact VBoxManage bridged-interface name to override,
    # e.g. 'Intel(R) Wi-Fi 6 AX201 160MHz'.
    BridgeAdapter        = ''

    # Windows Server 2022 ISO. Leave blank to auto-detect the newest
    # *.iso in this folder (recommended for portability). Set an explicit
    # path only if multiple ISOs are present.
    ISOPath              = 'D:\SAM_LAB\SERVER_EVAL_x64FRE_en-us.iso'

    # ---- Task Area 04: Server Rename ----------------------------------
    # Max 15 characters. Letters, numbers, hyphens. No spaces or underscores.
    ServerName           = 'Lab-Server-01'

    # ---- Task Area 02/03: Section Administrator Password ---------------
    # Format: <section>@BatStateU  (capital B, S, U; no spaces)
    # Examples: 3106@BatStateU, 3107@BatStateU, 3108@BatStateU
    SectionAdminPassword = '3106@BatStateU'

    # ---- Task Area 05: File and Storage Services -----------------------
    BaseSharePath        = 'C:\Shares'

    Departments          = @{
        IT      = @{ Password = 'Tech#Dept2026';   FolderName = 'IT_Share''it.txt' }
        HR      = @{ Password = 'People#Dept2026'; FolderName = 'HR_Share''hr.txt' }
        Manager = @{ Password = 'Lead#Dept2026';   FolderName = 'Manager_Share''manager.txt' }
    }

    PublicShare          = @{
        FolderName = 'Public_Share'
        FileName   = 'public.txt'
    }

    # ---- Task Area 06: Print and Document Services ---------------------
    # Existing port. Common choices: LPT1: or FILE:
    PrinterPort          = 'LPT1:'

    # Must match the instruction sheet exactly. Share name = printer name.
    PrinterName          = 'Office-Printer'
}
