#!/usr/bin/env python3
"""
Gets latest release of Odin from GitHub
"""

import os
import sys
import platform
import subprocess
import urllib.request
import urllib.error
import zipfile
import tarfile
import shutil
import json
import ssl
from pathlib import Path

class OdinInstaller:
    def __init__(self):
        self.system = platform.system().lower()
        self.arch = platform.machine().lower()
        self.home = Path.home()
        self.odin_dir = self.home / "odin"
        
        # GitHub API endpoints
        self.github_api_latest = "https://api.github.com/repos/odin-lang/Odin/releases/latest"
        self.github_api_releases = "https://api.github.com/repos/odin-lang/Odin/releases"
        self.github_releases_page = "https://github.com/odin-lang/Odin/releases"
        
    def get_latest_version_from_api(self):
        """Get latest release from GitHub API"""
        try:
            # Create SSL context that doesn't verify certificate (for older Python versions)
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            
            req = urllib.request.Request(
                self.github_api_latest,
                headers={'User-Agent': 'Odin-Installer/1.0', 'Accept': 'application/vnd.github.v3+json'}
            )
            
            with urllib.request.urlopen(req, context=ssl_context, timeout=30) as response:
                data = json.loads(response.read().decode())
                return data
        except urllib.error.HTTPError as e:
            if e.code == 403:
                print("[WARNING] GitHub API rate limit reached. Trying alternative method...")
                return self.get_latest_version_from_webpage()
            else:
                raise e
        except Exception as e:
            print(f"[WARNING] API method failed: {e}")
            return self.get_latest_version_from_webpage()
    
    def get_latest_version_from_webpage(self):
        """Fallback: Get latest release by scraping the releases page"""
        import re
        try:
            req = urllib.request.Request(
                self.github_releases_page,
                headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'}
            )
            with urllib.request.urlopen(req, timeout=30) as response:
                html = response.read().decode()
                # Find latest version tag pattern
                match = re.search(r'/odin-lang/Odin/releases/tag/([^"]+)', html)
                if match:
                    version = match.group(1)
                    print(f"[INFO] Found latest version: {version}")
                    # Now get the assets for this version
                    return self.get_release_assets(version)
                else:
                    raise Exception("Could not find version in HTML")
        except Exception as e:
            print(f"[ERROR] Failed to get release info: {e}")
            return None
    
    def get_release_assets(self, version):
        """Get release assets for a specific version"""
        try:
            api_url = f"https://api.github.com/repos/odin-lang/Odin/releases/tags/{version}"
            req = urllib.request.Request(
                api_url,
                headers={'User-Agent': 'Odin-Installer/1.0', 'Accept': 'application/vnd.github.v3+json'}
            )
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.loads(response.read().decode())
        except Exception as e:
            print(f"[ERROR] Failed to get assets: {e}")
            return None
    
    def get_os_arch(self):
        """Get OS and architecture string for Odin release"""
        arch_map = {
            'amd64': 'amd64',
            'x86_64': 'amd64',
            'arm64': 'arm64',
            'aarch64': 'arm64'
        }
        
        arch = arch_map.get(self.arch, self.arch)
        
        os_map = {
            'windows': 'windows',
            'darwin': 'macos',
            'linux': 'linux'
        }
        
        os_name = os_map.get(self.system)
        if not os_name:
            print(f"[ERROR] Unsupported OS: {self.system}")
            sys.exit(1)
            
        return f"{os_name}-{arch}"
    
    def download_with_progress(self, url, filename):
        """Download file with progress bar"""
        try:
            print(f"[INFO] Downloading: {url}")
            
            # Create request with user agent
            req = urllib.request.Request(
                url,
                headers={'User-Agent': 'Mozilla/5.0'}
            )
            
            with urllib.request.urlopen(req, timeout=60) as response:
                total_size = int(response.headers.get('content-length', 0))
                downloaded = 0
                
                with open(filename, 'wb') as f:
                    while True:
                        chunk = response.read(8192)
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded += len(chunk)
                        
                        if total_size > 0:
                            percent = (downloaded / total_size) * 100
                            bar_length = 40
                            filled = int(bar_length * downloaded / total_size)
                            bar = '█' * filled + '░' * (bar_length - filled)
                            print(f'\rProgress: |{bar}| {percent:.1f}% ({downloaded}/{total_size} bytes)', end='')
                            sys.stdout.flush()
                
                print()  # New line after progress
                return True
                
        except Exception as e:
            print(f"\n[ERROR] Download failed: {e}")
            return False
    
    def install(self):
        """Main installation process"""
        print("=" * 60)
        print("Odin Programming Language Installer")
        print(f"System: {self.system} {self.arch}")
        print("Getting latest release from GitHub...")
        print("=" * 60)
        
        # Get latest release information
        release = self.get_latest_version_from_api()
        if not release:
            print("[ERROR] Could not fetch release information")
            sys.exit(1)
        
        version = release.get('tag_name', 'unknown')
        print(f"[INFO] Latest version: {version}")
        
        # Find appropriate binary
        target = self.get_os_arch()
        print(f"[INFO] Looking for: {target}")
        
        asset_url = None
        asset_name = None
        
        for asset in release.get('assets', []):
            if target in asset['name'].lower():
                asset_url = asset['browser_download_url']
                asset_name = asset['name']
                print(f"[INFO] Found: {asset_name}")
                break
        
        if not asset_url:
            print(f"[ERROR] No binary found for {target}")
            print("\nAvailable binaries for this release:")
            for asset in release.get('assets', []):
                print(f"  - {asset['name']}")
            print(f"\nYou can manually download from: {self.github_releases_page}")
            sys.exit(1)
        
        # Prepare installation
        if self.odin_dir.exists():
            response = input(f"\nOdin already installed at {self.odin_dir}. Overwrite? (y/n): ")
            if response.lower() != 'y':
                print("Installation cancelled")
                return
            shutil.rmtree(self.odin_dir)
        
        self.odin_dir.mkdir(parents=True)
        
        # Download
        temp_file = self.home / f".odin_temp_{asset_name}"
        if not self.download_with_progress(asset_url, temp_file):
            sys.exit(1)
        
        # Extract
        print(f"[INFO] Extracting to {self.odin_dir}")
        try:
            if asset_name.endswith('.zip'):
                with zipfile.ZipFile(temp_file, 'r') as zip_ref:
                    zip_ref.extractall(self.odin_dir)
            elif asset_name.endswith('.tar.gz'):
                with tarfile.open(temp_file, 'r:gz') as tar_ref:
                    tar_ref.extractall(self.odin_dir)
            else:
                print(f"[ERROR] Unknown archive format: {asset_name}")
                sys.exit(1)
        except Exception as e:
            print(f"[ERROR] Extraction failed: {e}")
            sys.exit(1)
        
        temp_file.unlink()
        
        # Make executable on Unix
        if self.system != 'windows':
            odin_exe = self.odin_dir / "odin"
            if odin_exe.exists():
                odin_exe.chmod(0o755)
                print(f"[INFO] Made {odin_exe} executable")
        
        print("\n" + "=" * 60)
        print("[SUCCESS] Odin installed successfully!")
        print(f"Location: {self.odin_dir}")
        
        if self.system == 'windows':
            odin_exe = self.odin_dir / "odin.exe"
            print(f"\nAdd to PATH manually or run: set PATH=%PATH%;{self.odin_dir}")
        else:
            print(f"\nAdd to PATH by adding this line to ~/.bashrc or ~/.zshrc:")
            print(f'export PATH="{self.odin_dir}:$PATH"')
        
        print("\nTest your installation:")
        if self.system == 'windows':
            print(f'  {self.odin_dir}\\odin.exe version')
        else:
            print(f'  {self.odin_dir}/odin version')
        print("=" * 60)

def main():
    try:
        installer = OdinInstaller()
        installer.install()
    except KeyboardInterrupt:
        print("\n\nInstallation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()