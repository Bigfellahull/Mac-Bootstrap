# Windows development in Parallels

Parallels is required only on the work mini. The Air and personal mini profiles
do not install it. The Windows VM provides the build and runtime environment
for Windows-specific development, including .NET Framework, classic ASP.NET
and native C++ applications.

`bin/mac apply work-mini` installs Parallels on macOS. Windows setup, guest
tools, developer tools, package authentication and licences remain manual.
Keep Windows SDKs and compilers inside the guest. Record application-specific
dependencies and local machine details in private project documentation.

## Guest prerequisites

Create or restore a Windows VM supported by the Mac and Parallels installation.
Install Parallels Tools, complete Windows updates and sign into the intended
Windows development account. On Apple silicon, distinguish the ARM64 guest
architecture from each application's x86, x64 or ARM64 build target.

Install Git for Windows and Visual Studio Build Tools with the workloads
required by the applications:

| Workload | Build Tools workload ID | Purpose |
|---|---|---|
| MSBuild | `Microsoft.VisualStudio.Workload.MSBuildTools` | Core build tooling |
| C++ | `Microsoft.VisualStudio.Workload.VCTools` | Native Windows compilation |
| .NET desktop | `Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools` | .NET Framework desktop applications |
| Web | `Microsoft.VisualStudio.Workload.WebBuildTools` | Classic ASP.NET and web application targets |

Select individual components to match the project requirements:

- The required MSVC platform toolsets, target architectures and Windows SDK.
- The exact .NET Framework targeting packs and SDK tools used by the projects.
  A newer targeting pack does not replace an older project's reference assemblies.
- A compatible .NET SDK for SDK-style projects, plus the runtime families and
  architectures needed to execute their outputs.
- NuGet restore and test tools. Install a current NuGet command-line client
  separately when a project's restore workflow requires `nuget.exe`.
- WCF build support, CMake, TypeScript or other optional tooling only where
  required by the workload.

Consult Microsoft's
[Build Tools component catalogue](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-build-tools)
for the selected Visual Studio version. Use Visual Studio MSBuild for projects
that depend on its classic web, COM or component-licensing tasks; do not assume
the .NET SDK's `dotnet build` is interchangeable.

Rust tooling for builds coordinated from Ubuntu follows the separate
[Windows native build commissioning guide](https://github.com/Bigfellahull/Dev-Machine/blob/main/docs/windows-builds.md).
Install other language runtimes and cloud CLIs in the guest only when needed.
Authentication and commercial component activation remain interactive.

## Shared files and execution context

Configure a Parallels share containing the required work repositories or build
transfer directory. Use its UNC path, `\\Mac\SHARE\PROJECT`, for scripts that
support UNC paths. Mapped drive letters can change between sessions. Keep
sibling repositories together when relative project references require them.

After Windows has booted and the development user has signed in, check access
from macOS. Replace `Windows 11`, `SHARE` and `PROJECT` with local values:

```bash
prlctl list -a
prlctl exec 'Windows 11' --current-user cmd.exe /d /c echo READY
prlctl exec 'Windows 11' --current-user powershell.exe -NoProfile -Command \
  'Test-Path "\\Mac\SHARE\PROJECT"'
```

Use `--current-user` for builds so they use the developer's shares, NuGet
configuration and licences. The default SYSTEM context has different access
and configuration. In a Windows `cmd.exe` session, use
`pushd \\Mac\SHARE\PROJECT` when a tool requires a drive-backed working directory.
Keep machine names, actual share paths and account details in local settings.

## Build and runtime compatibility

Use each project's declared configuration and platform. A solution may map
`Any CPU` to an x86 application or use different platform names at solution and
project level. Running a build in an ARM64 guest does not change those targets.

Match the native project's effective `PlatformToolset` to an installed compiler
toolset. Installing a newer compiler or setting an unrelated local property
does not retarget a project. Preserve required older toolsets, or review and
test an explicit retargeting change in the project. See Microsoft's
[missing-toolset guidance](https://learn.microsoft.com/en-us/visualstudio/msbuild/errors/msb8020).

For managed applications, distinguish build-time SDKs and targeting packs from
runtime requirements. Framework-dependent output needs a compatible runtime
of the correct architecture. A newer SDK does not prove that an older target
can run, and .NET does not roll forward across major versions by default. See
[.NET version selection](https://learn.microsoft.com/en-us/dotnet/core/versions/selection).

Restore all package formats used by the solution, including `packages.config`
and PackageReference where both are present. Follow the project's lock-file
policy and preserve required native libraries or sibling source dependencies.
Do not use existing output folders as evidence that a clean build has all its
dependencies.

## Packages, licences and packaging

Keep private-feed URLs, credentials and organisation-specific configuration
outside this public repository. Use user-level NuGet configuration or an
approved credential provider, and authenticate as the Windows build user.
Never place feed credentials in a `prlctl` command.

Commercial controls may need vendor assemblies, package access, build-time
licences or runtime activation. Follow the vendor's instructions for the exact
version in use. Licence files, signing material and account identities must
remain outside this repository.

COM/ActiveX registration, hardware-key drivers and native redistributables are
separate runtime dependencies. Match their architecture to the application and
commission only the features required by the workload.

Visual Studio Build Tools does not include the full IDE's `devenv.com`.
Legacy `.vdproj` installer projects need a separate Visual Studio IDE and
Installer Projects workflow. Verify packaging and signing separately from
application compilation.

## Local web applications and services

Install IIS Express or enable the required IIS features when an application
needs classic ASP.NET hosting. WCF applications may host themselves in a
development process; enable Windows activation features or install services
only where that hosting model requires them.

Verify required modules, bindings, certificates and URL reservations explicitly.
A module DLL on disk does not prove that the web server has registered it.
Preserve the application's intended HTTPS behaviour in tracked configuration.
Keep any deliberate local hosting variation in private development settings.

Use separate ports for applications that run together. Prefer loopback bindings
for guest-only access. Browser access from another machine requires explicit
routing, bindings and firewall configuration. Confirm development database and
storage destinations before launching applications that run migrations or
background jobs on startup.

## Database boundary

Development database containers belong to the work mini's OrbStack runtime.
Configure Windows applications to connect to their intended database through
the host's explicitly published endpoint. Do not install Docker Desktop,
Colima, Podman or a second guest container runtime to satisfy a project's local
container defaults.

Keep databases, volumes and credentials scoped to their project and work
profile. Record their names, addresses and connection settings privately.
Publish ports only on the intended interfaces and verify reachability from
Windows; a host loopback binding is not automatically reachable from the VM.
Protect existing data before changing containers or volumes. Mac bootstrap
does not create, migrate or restore application databases.

## Verification after commissioning

Discover the installed Build Tools path in Windows PowerShell:

```powershell
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
if (-not $vs) { throw 'Visual Studio MSBuild was not found.' }
& "$vs\MSBuild\Current\Bin\MSBuild.exe" -version -nologo
Get-ChildItem 'C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework' -Directory
dotnet --list-sdks
dotnet --list-runtimes
```

Run the checks relevant to the selected workloads. On a guest with multiple
.NET architectures, repeat the runtime check using each required architecture's
`dotnet.exe`; the executable on PATH reports only its own installation.

Then restore and build each required configuration from an isolated checkout
using its project's private build guide. Test application launch, database
access, native components and required endpoints separately from compilation.
Verify installer production and signing where needed. Record machine inventory
and application-specific results privately; `bin/mac verify work-mini` checks
the macOS profile, not these Windows workflows.
