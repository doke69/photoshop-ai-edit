"""Build CCX everywhere; --installers also builds macOS universal and Windows installers on macOS."""
import argparse
import hashlib
import json
import platform
import plistlib
import shutil
import subprocess
import base64
import tempfile
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
plugin = root / 'plugin'
manifest = json.loads((plugin / 'manifest.json').read_text(encoding='utf-8'))
version = manifest['version']
dist = root / 'dist'
dist.mkdir(exist_ok=True)

def archive_tree(folder, output, prefix=''):
    with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file() and path.name not in ('.uxprc', '.DS_Store'):
                archive.write(path, str(Path(prefix) / path.relative_to(folder)))
    with ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('Archive integrity check failed: ' + str(output))
    return output

def copy_plugin(destination):
    shutil.copytree(plugin, destination, ignore=shutil.ignore_patterns('.uxprc', '.DS_Store'))

def render_guide():
    guide = (root / 'installer/guide.html').read_text(encoding='utf-8').replace('{{VERSION}}', version)
    images = {
        'ICON_DATA': ('image/png', root / 'assets/branding/app-icon.png'),
        'SHOT_ENTRY': ('image/jpeg', root / 'assets/guide/site-api-entry.jpg'),
        'SHOT_HOME': ('image/jpeg', root / 'assets/guide/api-home.jpg'),
        'SHOT_NAV': ('image/jpeg', root / 'assets/guide/api-keys-navigation.jpg'),
        'SHOT_FORM': ('image/jpeg', root / 'assets/guide/api-create-form.jpg'),
        'SHOT_SUCCESS': ('image/jpeg', root / 'assets/guide/api-created-proof.jpg'),
    }
    for name, (mime, path) in images.items():
        guide = guide.replace('{{' + name + '}}', 'data:' + mime + ';base64,' + base64.b64encode(path.read_bytes()).decode())
    if '{{' in guide:
        raise RuntimeError('Guide contains unresolved placeholders')
    return guide

def make_icns(source, output, iconset):
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            subprocess.run(['sips', '-z', str(size * scale), str(size * scale), str(source), '--out', str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['xcrun', 'iconutil', '-c', 'icns', str(iconset), '-o', str(output)], check=True)

def build_windows_payload():
    """Portable inputs for the native Windows build; no Mac tools required."""
    with tempfile.TemporaryDirectory(prefix='ai-edit-windows-') as temporary:
        payload = Path(temporary)
        copy_plugin(payload / 'plugin')
        (payload / '安装与使用指南.html').write_text(render_guide(), encoding='utf-8')
        for name in ('install.ps1', 'InstallerCore.ps1'):
            text = (root / 'installer/windows' / name).read_text(encoding='utf-8-sig')
            (payload / name).write_bytes(text.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8-sig'))
        return archive_tree(payload, dist / 'windows-payload.zip')

def build_installers():
    if platform.system() != 'Darwin':
        raise RuntimeError('Universal macOS installer requires macOS and Xcode command line tools.')
    guide = render_guide()
    with tempfile.TemporaryDirectory(prefix='ai-edit-package-') as temporary:
        work = Path(temporary)
        app = work / 'Install Photoshop AI Edit.app'
        contents = app / 'Contents'
        resources = contents / 'Resources'
        binaries = contents / 'MacOS'
        resources.mkdir(parents=True)
        binaries.mkdir()
        copy_plugin(resources / 'plugin')
        (resources / '安装与使用指南.html').write_text(guide)
        shutil.copy2(root / 'assets/branding/app-icon.png', resources / 'AppIcon.png')
        make_icns(resources / 'AppIcon.png', resources / 'AppIcon.icns', work / 'AppIcon.iconset')
        disk_icon = work / 'DiskIcon.icns'
        make_icns(root / 'assets/branding/mounted-disk.png', disk_icon, work / 'DiskIcon.iconset')
        info = {'CFBundleExecutable': 'AIEditInstaller', 'CFBundleIdentifier': 'com.local.lk888.psedit.installer',
                'CFBundleName': 'Install Photoshop AI Edit', 'CFBundleDisplayName': '安装 Photoshop AI Edit',
                'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': version, 'CFBundleVersion': version,
                'LSMinimumSystemVersion': '12.0', 'NSHighResolutionCapable': True, 'CFBundleIconFile': 'AppIcon.icns', 'CFBundleIconName': 'AppIcon'}
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        slices = []
        for architecture in ('arm64', 'x86_64'):
            binary = work / ('installer-' + architecture)
            subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(work / 'swift-cache'),
                            '-target', architecture + '-apple-macos12.0',
                            str(root / 'installer/macos/InstallerCore.swift'), str(root / 'installer/macos/main.swift'),
                            '-o', str(binary)], check=True)
            slices.append(str(binary))
        executable = binaries / 'AIEditInstaller'
        subprocess.run(['xcrun', 'lipo', '-create', *slices, '-output', str(executable)], check=True)
        executable.chmod(0o755)
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
        mac = archive_tree(app, dist / f'Photoshop-AI-Edit-{version}-macOS-universal.zip', app.name)
        image_root = work / 'dmg'
        image_root.mkdir()
        shutil.copytree(app, image_root / app.name)
        (image_root / '安装与使用指南.html').write_text(guide)
        (image_root / '请先阅读.txt').write_text('Photoshop AI Edit 安装与卸载\n\n双击 Install Photoshop AI Edit.app，选择安装 / 更新或卸载插件。\n这是 Photoshop 插件安装器，无需拖入 Applications。\n操作前保存文件并完全退出 Photoshop。卸载保留 API Key 和任务历史。\n\n支持 Photoshop 25.0（2024）及以上；Apple Silicon / Intel 通用。\n安装器未取得 Apple 开发者签名或公证，若系统阻止打开，可改用 CCX 与 OpenUXP。\n')
        dmg = dist / f'Photoshop-AI-Edit-{version}-macOS-universal.dmg'
        icon_helper = work / 'set-file-icon'
        subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(work / 'swift-cache'), str(root / 'installer/macos/SetFileIcon.swift'), '-o', str(icon_helper)], check=True)
        shutil.copy2(disk_icon, image_root / '.VolumeIcon.icns')
        subprocess.run(['xcrun', 'SetFile', '-a', 'C', str(image_root)], check=True)
        writable_image = work / 'installer-rw.dmg'
        subprocess.run(['hdiutil', 'create', '-volname', 'Photoshop AI Edit', '-fs', 'HFS+', '-srcfolder', str(image_root), '-format', 'UDRW', '-ov', str(writable_image)], check=True)
        mount = work / 'mounted-volume'
        mount.mkdir()
        subprocess.run(['hdiutil', 'attach', '-nobrowse', '-mountpoint', str(mount), str(writable_image)], check=True)
        try:
            subprocess.run([str(icon_helper), str(disk_icon), str(mount)], check=True)
            subprocess.run(['xcrun', 'SetFile', '-a', 'C', str(mount)], check=True)
        finally:
            subprocess.run(['hdiutil', 'detach', str(mount)], check=True)
        subprocess.run(['hdiutil', 'convert', str(writable_image), '-format', 'UDZO', '-ov', '-o', str(dmg)], check=True)
        subprocess.run([str(icon_helper), str(disk_icon), str(dmg)], check=True)
        subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
        windows = work / f'Photoshop-AI-Edit-{version}-Windows'
        windows.mkdir()
        copy_plugin(windows / 'plugin')
        (windows / '安装与使用指南.html').write_text(guide)
        for name in ('Install.cmd', 'Uninstall.cmd', 'install.ps1', 'InstallerCore.ps1'):
            text = (root / 'installer/windows' / name).read_text(encoding='utf-8-sig')
            (windows / name).write_bytes(text.replace('\r\n', '\n').replace('\n', '\r\n').encode('utf-8-sig' if name.endswith('.ps1') else 'ascii'))
        win = archive_tree(windows, dist / (windows.name + '.zip'), windows.name)
        (dist / f'安装与使用指南-v{version}.html').write_text(guide)
        return [dmg, mac, win]

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--installers', action='store_true')
    parser.add_argument('--windows-payload', action='store_true')
    args = parser.parse_args()
    if args.windows_payload:
        print(build_windows_payload())
        raise SystemExit(0)
    artifacts = [archive_tree(plugin, dist / f'photoshop-ai-edit-LK888-{version}.ccx')]
    if args.installers:
        artifacts.extend(build_installers())
    sums = dist / f'SHA256SUMS-v{version}.txt'
    sums.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in artifacts))
    for path in [*artifacts, sums]:
        print(path)
