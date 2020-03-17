#!/usr/bin/env bash

source="${BASH_SOURCE[0]}"
scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"

base_uri='https://netcorenativeassets.blob.core.windows.net/resource-packages/external'
install_directory=''
clean=false
force=false
download_retries=5
retry_wait_time_seconds=30
global_json_file="$(dirname "$(dirname "${scriptroot}")")/global.json"
declare -A native_assets

. $scriptroot/pipeline-logging-functions.sh
. $scriptroot/native/common-library.sh

while (($# > 0)); do
  lowerI="$(echo $1 | awk '{print tolower($0)}')"
  case $lowerI in
    --baseuri)
      base_uri=$2
      shift 2
      ;;
    --installdirectory)
      install_directory=$2
      shift 2
      ;;
    --clean)
      clean=true
      shift 1
      ;;
    --force)
      force=true
      shift 1
      ;;
    --donotabortonfailure)
      donotabortonfailure=true
      shift 1
      ;;
    --donotdisplaywarnings)
      donotdisplaywarnings=true
      shift 1
      ;;
    --downloadretries)
      download_retries=$2
      shift 2
      ;;
    --retrywaittimeseconds)
      retry_wait_time_seconds=$2
      shift 2
      ;;
    --help)
      echo "Common settings:"
      echo "  --installdirectory                  Directory to install native toolset."
      echo "                                      This is a command-line override for the default"
      echo "                                      Install directory precedence order:"
      echo "                                          - InstallDirectory command-line override"
      echo "                                          - NETCOREENG_INSTALL_DIRECTORY environment variable"
      echo "                                          - (default) %USERPROFILE%/.netcoreeng/native"
      echo ""
      echo "  --clean                             Switch specifying not to install anything, but cleanup native asset folders"
      echo "  --donotabortonfailure               Switch specifiying whether to abort native tools installation on failure"
      echo "  --donotdisplaywarnings              Switch specifiying whether to display warnings during native tools installation on failure"
      echo "  --force                             Clean and then install tools"
      echo "  --help                              Print help and exit"
      echo ""
      echo "Advanced settings:"
      echo "  --baseuri <value>                   Base URI for where to download native tools from"
      echo "  --downloadretries <value>           Number of times a download should be attempted"
      echo "  --retrywaittimeseconds <value>      Wait time between download attempts"
      echo ""
      exit 0
      ;;
  esac
done

function ReadGlobalJsonNativeTools {
  # Get the native-tools section from the global.json.
  local native_tools_section=$(cat $global_json_file | awk '/"native-tools"/,/}/')
  # Only extract the contents of the object.
  local native_tools_list=$(echo $native_tools_section | awk -F"[{}]" '{print $2}')
  native_tools_list=${native_tools_list//[\" ]/}
  native_tools_list=$( echo "$native_tools_list" | sed 's/\s//g' | sed 's/,/\n/g' )

  local old_IFS=$IFS
  while read -r line; do
    # Lines are of the form: 'tool:version'
    IFS=:
    while read -r key value; do
     native_assets[$key]=$value
    done <<< "$line"
  done <<< "$native_tools_list"
  IFS=$old_IFS

  return 0;
}

native_base_dir=$install_directory
if [[ -z $install_directory ]]; then
  native_base_dir=$(GetNativeInstallDirectory)
fi

install_bin="${native_base_dir}/bin"
installed_any=false

ReadGlobalJsonNativeTools

if [[ ${#native_assets[@]} -eq 0 ]]; then
  echo "No native tools defined in global.json"
  exit 0;
else
  native_installer_dir="$scriptroot/native"
  for tool in "${!native_assets[@]}"
  do
    tool_version=${native_assets[$tool]}
    installer_path="$native_installer_dir/install-$tool.sh"
    installer_command="$installer_path"
    installer_command+=" --baseuri $base_uri"
    installer_command+=" --installpath $install_bin"
    installer_command+=" --version $tool_version"
    echo $installer_command

    if [[ $force = true ]]; then
      installer_command+=" --force"
    fi

    if [[ $clean = true ]]; then
      installer_command+=" --clean"
    fi

    if [[ -a $installer_path ]]; then
      $installer_command
      if [[ $? != 0 ]]; then
        if [[ $donotabortonfailure = true ]]; then
          if [[ $donotdisplaywarnings != true ]]; then
            Write-PipelineTelemetryError -category 'NativeToolsBootstrap' "Execution Failed"
          fi
        else
          Write-PipelineTelemetryError -category 'NativeToolsBootstrap' "Execution Failed"
          exit 1
        fi
      else
        $installed_any = true
      fi
    else
      if [[ $donotabortonfailure == true ]]; then
        if [[ $donotdisplaywarnings != true ]]; then
          Write-PipelineTelemetryError -category 'NativeToolsBootstrap' "Execution Failed: no install script"
        fi
      else
        Write-PipelineTelemetryError -category 'NativeToolsBootstrap' "Execution Failed: no install script"
        exit 1
      fi
    fi
  done
fi

if [[ $clean = true ]]; then
  exit 0
fi

if [[ -d $install_bin ]]; then
  echo "Native tools are available from $install_bin"
  echo "##vso[task.prependpath]$install_bin"
else
  if [[ $installed_any = true ]]; then
    Write-PipelineTelemetryError -category 'NativeToolsBootstrap' "Native tools install directory does not exist, installation failed"
    exit 1
  fi
fi

exit 0
