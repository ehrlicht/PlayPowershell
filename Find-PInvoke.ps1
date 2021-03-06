<#
.Synopsis
    Cracks open a .NET assembly using .NET ReflectionOnlyLoad and gathers 
    information on all the Platform Invoke methods.
.Description
    Cracks open a .NET assembly using .NET ReflectionOnlyLoad and gathers 
    information on all the Platform Invoke methods. The DllImportAttribute 
    methods are found and the script gathers the following information:
    AssemblyName, DllName, EntryPoint, TypeName, MethodName, MethodSig, DllImport.
.Parameter LiteralPath
    Specifies the path to .NET assembly to process. Unlike Path, the value of LiteralPath is used exactly as it is typed. 
    No characters are interpreted as wildcards. If the path includes escape characters, enclose it in 
    single quotation marks. Single quotation marks tell Windows PowerShell not to interpret any characters 
    as escape sequences.
.Parameter Path 
    Specifies the path to the .NET assembly to process. Wildcards are permitted. 
    The parameter name ("-Path" or "-FilePath") is optional.
.Parameter SearchPaths
    The .NET assembly being searched may depend on other .NET asssemblies.  If those assemblies are not
    located in the same dir as the assembly being searched or in a well known .NET dir, then you should
    specify the directories containing the other assemblies.
.Example
    C:\PS> Find-PInvoke Acme.dll
    Finds information on all the PInvokes in the the specified dll.
.Notes
    Author:  Keith Hill
    License: BSD, http://en.wikipedia.org/wiki/BSD_license     
    Copyright (c) 2009, Keith Hill
    All rights reserved.

    Redistribution and use in source and binary forms, with or without 
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, 
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright 
      notice, this list of conditions and the following disclaimer in the 
      documentation and/or other materials provided with the distribution.
    * Neither the name of the COPYRIGHT HOLDERS nor the names of its contributors 
      may be used to endorse or promote products derived from this software 
      without specific prior written permission.
    
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
    AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
    ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
    LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.    
#>
#requires -version 2.0
[CmdletBinding(DefaultParameterSetName="Path")]
param(
    [Parameter(Mandatory=$true, 
               Position=0, 
               ParameterSetName="Path", 
               ValueFromPipeline=$true, 
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to assembly")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Path,
    
    [Alias("PSPath")]
    [Parameter(Mandatory=$true, 
               Position=0, 
               ParameterSetName="LiteralPath", 
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to assembly")]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $LiteralPath,
    
    [Parameter()]
    [string[]]
    $SearchPaths
)

Begin
{
    Set-StrictMode -Version 2.0

    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Reflection;
using Microsoft.Win32;

namespace ReflectionOnlyLoad
{
    public class AssemblyLoader : IDisposable
    {
        private readonly string _rootAssemblyPath;
        private string[] _searchPaths;
        
        public AssemblyLoader(string path, string[] searchPaths)
        {
            _rootAssemblyPath = path;
            _searchPaths = searchPaths ?? new string[0];
            AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve += ReflectionOnlyAssemblyResolveHandler;
        }

        ~AssemblyLoader()
        {
            Dispose(false);
        }

        public Assembly Load()
        {
            Assembly assembly = Assembly.ReflectionOnlyLoadFrom(_rootAssemblyPath);
            return assembly;
        }

        private Assembly ReflectionOnlyAssemblyResolveHandler(object sender, ResolveEventArgs args)
        {
            Assembly assembly;

            AssemblyName assemblyName = new AssemblyName(args.Name);
            string assemblyFilename   = assemblyName.Name + ".dll";
            string localAssemblyPath  = Path.Combine(Path.GetDirectoryName(_rootAssemblyPath), assemblyFilename);
            if (File.Exists(localAssemblyPath))
            {
                assembly = Assembly.ReflectionOnlyLoadFrom(localAssemblyPath);
            }
            else
            {
                try
                {
                    assembly = Assembly.ReflectionOnlyLoad(args.Name);
                }
                catch (FileNotFoundException)
                {
                    string assemblyPath = "";
                    string version = assemblyName.Version.ToString();
                    string regkeyPath = @"SOFTWARE\Microsoft\.NETCompactFramework\v" + version + @"\InstallRoot";
                    using (RegistryKey key = Registry.LocalMachine.OpenSubKey(regkeyPath, false))
                    {
                        if (key != null)
                        {
                            string cfRoot = key.GetValue(null, "").ToString();
                            assemblyPath = Path.Combine(cfRoot, @"WindowsCE\" + assemblyFilename);
                        }
                    }
                    
                    if (!File.Exists(assemblyPath))
                    {
                        // If that path doesn't exist, then try the user specified search paths
                        foreach (string searchPath in _searchPaths)
                        {
                            string path = Path.Combine(searchPath, assemblyFilename);
                            if (File.Exists(path))
                            {
                                assemblyPath = path;
                                break;
                            }
                        }
                        if (!File.Exists(assemblyPath)) { throw; }
                    }
                    
                    assembly = Assembly.ReflectionOnlyLoadFrom(assemblyPath);
                }
            }
            return assembly;
        }

        public void Dispose()
        {
            GC.SuppressFinalize(this);
            Dispose(true);
        }

        private void Dispose(bool disposing)
        {
            AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve -= ReflectionOnlyAssemblyResolveHandler;
        }
    }
}
'@    

    $PInvokeImpl = 0x2000       
    $DllImportRegex = 'System\.Runtime\.InteropServices\.DllImportAttribute'
    
    function FindPInvokeImpl($path)
    {
        $assemblyLoader = New-Object ReflectionOnlyLoad.AssemblyLoader $path,$SearchPaths
        try
        {
            $asm = $assemblyLoader.Load()
            try
            {
                $types = @($asm.GetTypes())
            }
            catch
            {
                if ($_.Exception.InnerException -is [System.Reflection.ReflectionTypeLoadException])
                {
                    $_.Exception.InnerException.LoaderExceptions | Foreach { Write-Warning $_.Message }
                }
                else
                {
                    Write-Warning $_.Exception.InnerException.Message                    
                }                                
                throw $_
            }
            
            foreach ($type in $types)
            {
                $bindingFlags = 'Instance','Static','Public','NonPublic'
                foreach ($methodInfo in @($type.GetMethods($bindingFlags)))
                {
                    if (($methodInfo.Attributes -band $PInvokeImpl) -eq $PInvokeImpl)
                    {
                        Write-Verbose "Find-PInvoke found pinvokeimpl $($type.FullName)$($methodInfo.Name)"
                        $attrs = [System.Reflection.CustomAttributeData]::GetCustomAttributes($methodInfo)
                        $dllImportAttr = @($attrs | Where {$_.ToString() -match $DllImportRegex})[0]
                        
                        $methodSig  = $methodInfo.ToString() -replace '(\S+)\s+(.*)','$2 as $1'
                        $dllName    = $dllImportAttr.ConstructorArguments[0].Value.Trim('"')
                        if (![System.IO.Path]::HasExtension($dllName))
                        {
                            $dllName += ".dll"
                        }
                        $entryPoint = $dllImportAttr.NamedArguments | 
                                          Where {$_.MemberInfo.Name -eq 'EntryPoint'} | 
                                          Foreach {$_.TypedValue.Value}
                                          
                        $props = @{
                            AssemblyName = (Split-Path $path -Leaf)
                            DllName      = $dllName 
                            EntryPoint   = $entryPoint
                            TypeName     = $type.FullName
                            MethodName   = $methodInfo.Name       
                            MethodSig    = $methodSig 
                            DllImport    = $dllImportAttr           
                        }
                        
                        $obj = new-object psobject -Property $props
                        $obj                                            
                    }
                }
            }
        }
        finally 
        {
            $assemblyLoader.Dispose()
        }
    }
}

Process
{
    if ($psCmdlet.ParameterSetName -eq "Path")
    {
        # In the -Path (non-literal) case we may need to resolve a wildcarded path
        $resolvedPaths = @()
        foreach ($apath in $Path) 
        {
            $resolvedPaths += @(Resolve-Path $apath | Foreach { $_.Path })
        }
    }
    else 
    {
        # Must be -LiteralPath
        $resolvedPaths = $LiteralPath
    }

    # Find PInvoke info for each specified path       
    foreach ($rpath in $resolvedPaths) 
    {
        $PathIntrinsics = $ExecutionContext.SessionState.Path
        if ($PathIntrinsics.IsProviderQualified($rpath))
        {
            # If path is provider qualified, remove the qualifier prefix
            $rpath = $PathIntrinsics.GetUnresolvedProviderPathFromPSPath($rpath)
        }
        
        Write-Verbose "$($pscmdlet.MyInvocation.MyCommand) processing $rpath"
        
        if (!(Test-Path $rpath))
        {
            Write-Error "'$path' doesn't exist"
            continue
        }
        
        FindPInvokeImpl $rpath
    }
}