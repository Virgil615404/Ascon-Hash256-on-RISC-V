$src_dir  = "D:\ascon\ascon.srcs"
$sim_dir  = "D:\ascon\ascon.sim"
$tb_file  = "$sim_dir\tb_cycles.sv"

# 收集所有 RTL 源文件
$sv_files = Get-ChildItem -Path $src_dir -Filter *.sv | % { $_.FullName }

# 编译
Write-Host "Compiling..."
xvlog -sv -i $src_dir ($sv_files + $tb_file)
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 细化
Write-Host "Elaborating..."
xelab tb_cycles -s tb_cycles_snap
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# 仿真
Write-Host "Simulating..."
xsim tb_cycles_snap -R