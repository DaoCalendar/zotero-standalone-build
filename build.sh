#!/bin/bash

# Copyright (c) 2011  Zotero
#                     Center for History and New Media
#                     George Mason University, Fairfax, Virginia, USA
#                     http://zotero.org
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

CALLDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$CALLDIR/config.sh"

[ "`uname`" != "Darwin" ]
MAC_NATIVE=$?
[ "`uname -o 2> /dev/null`" != "Cygwin" ]
WIN_NATIVE=$?

function usage {
	cat >&2 <<DONE
Usage: $0 [-p PLATFORMS] [-s DIR] [-v VERSION] [-c CHANNEL] [-d]
Options
 -p PLATFORMS        build for platforms PLATFORMS (m=Mac, w=Windows, l=Linux)
 -s DIR              build symlinked to Zotero checkout DIR (implies -d)
 -v VERSION          use version VERSION
 -c CHANNEL          use update channel CHANNEL
 -d                  don't package; only build binaries in staging/ directory
DONE
	exit 1
}

PACKAGE=1
while getopts "p:s:v:c:d" opt; do
	case $opt in
		p)
			BUILD_MAC=0
			BUILD_WIN32=0
			BUILD_LINUX=0
			for i in `seq 0 1 $((${#OPTARG}-1))`
			do
				case ${OPTARG:i:1} in
					m) BUILD_MAC=1;;
					w) BUILD_WIN32=1;;
					l) BUILD_LINUX=1;;
					*)
						echo "$0: Invalid platform option ${OPTARG:i:1}"
						usage
						;;
				esac
			done
			;;
		s)
			SYMLINK_DIR="$OPTARG"
			PACKAGE=0
			;;
		v)
			VERSION="$OPTARG"
			;;
		c)
			UPDATE_CHANNEL="$OPTARG"
			;;
		d)
			PACKAGE=0
			;;
		*)
			usage
			;;
	esac
	shift $((OPTIND-1)); OPTIND=1
done

if [ ! -z $1 ]; then
	usage
fi

BUILDID=`date +%Y%m%d`

shopt -s extglob
mkdir "$BUILDDIR"
rm -rf "$STAGEDIR"
mkdir "$STAGEDIR"
rm -rf "$DISTDIR"
mkdir "$DISTDIR"

if [ -z "$UPDATE_CHANNEL" ]; then UPDATE_CHANNEL="default"; fi

if [ ! -z "$SYMLINK_DIR" ]; then
	echo "Building Zotero from $SYMLINK_DIR"
	
	cp -RH "$SYMLINK_DIR" "$BUILDDIR/zotero"
	cd "$BUILDDIR/zotero"
	if [ $? != 0 ]; then
		exit
	fi
	REV=`git log -n 1 --pretty='format:%h'`
	VERSION="$DEFAULT_VERSION_PREFIX$REV"
	find . -depth -type d -name .git -exec rm -rf {} \;
	
	# Windows can't actually symlink; copy instead, with a note
	if [ "$WIN_NATIVE" == 1 ]; then
		echo "Windows host detected; copying files instead of symlinking"
		
		# Copy branding
		cp -R "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome/branding"
		find "$BUILDDIR/zotero/chrome/branding" -depth -type d -name .git -exec rm -rf {} \;
		find "$BUILDDIR/zotero/chrome/branding" -name .DS_Store -exec rm -f {} \;
	else	
		# Symlink chrome dirs
		rm -rf "$BUILDDIR/zotero/chrome/"*
		for i in `ls $SYMLINK_DIR/chrome`; do
			ln -s "$SYMLINK_DIR/chrome/$i" "$BUILDDIR/zotero/chrome/$i"
		done
		
		# Symlink translators and styles
		rm -rf "$BUILDDIR/zotero/translators" "$BUILDDIR/zotero/styles"
		ln -s "$SYMLINK_DIR/translators" "$BUILDDIR/zotero/translators"
		ln -s "$SYMLINK_DIR/styles" "$BUILDDIR/zotero/styles"
		
		# Symlink branding
		ln -s "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome/branding"
	fi
	
	# Add to chrome manifest
	echo "" >> "$BUILDDIR/zotero/chrome.manifest"
	cat "$CALLDIR/assets/chrome.manifest" >> "$BUILDDIR/zotero/chrome.manifest"
else
	echo "Building from bundled submodule"
	
	# Copy Zotero directory
	cp -RH "$CALLDIR/modules/zotero" "$BUILDDIR/zotero"
	cd "$BUILDDIR/zotero"
	REV=`git log -n 1 --pretty='format:%h'`
	
	if [ -z "$VERSION" ]; then
		VERSION="$DEFAULT_VERSION_PREFIX$REV"
	fi
	
	# Copy branding
	cp -R "$CALLDIR/assets/branding" "$BUILDDIR/zotero/chrome/branding"
	
	# Delete files that shouldn't be distributed
	find "$BUILDDIR/zotero/chrome" -depth -type d -name .git -exec rm -rf {} \;
	find "$BUILDDIR/zotero/chrome" -name .DS_Store -exec rm -f {} \;
	
	# Set version
	perl -pi -e "s/VERSION: \"[^\"]*\"/VERSION: \"$VERSION\"/" \
		"$BUILDDIR/zotero/chrome/content/zotero/xpcom/zotero.js"
	
	# Zip chrome into JAR
	cd "$BUILDDIR/zotero/chrome"
	# Checkout failed -- bail
	if [ $? -eq 1 ]; then
		exit;
	fi
	zip -0 -r -q ../zotero.jar .
	rm -rf "$BUILDDIR/zotero/chrome/"*
	mv ../zotero.jar .
	cd ..
	
	# Build translators.zip
	echo "Building translators.zip"
	cd "$BUILDDIR/zotero/translators"
	mkdir output
	counter=0;
	for file in *.js; do
		newfile=$counter.js;
		id=`grep -m 1 '"translatorID" *: *"' "$file" | perl -pe 's/.*"translatorID"\s*:\s*"(.*)".*/\1/'`
		label=`grep -m 1 '"label" *: *"' "$file" | perl -pe 's/.*"label"\s*:\s*"(.*)".*/\1/'`
		mtime=`grep -m 1 '"lastUpdated" *: *"' "$file" | perl -pe 's/.*"lastUpdated"\s*:\s*"(.*)".*/\1/'`
		echo $newfile,$id,$label,$mtime >> ../translators.index
		cp "$file" output/$newfile;
		counter=$(($counter+1))
	done;
	cd output
	zip -q ../../translators.zip *
	cd ../..
	
	# Delete translators directory except for deleted.txt
	mv translators/deleted.txt deleted.txt
	rm -rf translators
	
	# Build styles.zip with default styles
	if [ -d styles ]; then
		echo "Building styles.zip"
		
		cd styles
		zip -q ../styles.zip *.csl
		cd ..
		rm -rf styles
	fi
	
	# Adjust chrome.manifest
	echo "" >> "$BUILDDIR/zotero/chrome.manifest"
	cat "$CALLDIR/assets/chrome.manifest" >> "$BUILDDIR/zotero/chrome.manifest"
	
	# Copy updater.ini
	cp "$CALLDIR/assets/updater.ini" "$BUILDDIR/zotero"
	
	perl -pi -e 's/chrome\//jar:chrome\/zotero.jar\!\//g' "$BUILDDIR/zotero/chrome.manifest"
fi

# Adjust connector pref
perl -pi -e 's/pref\("extensions\.zotero\.httpServer\.enabled", false\);/pref("extensions.zotero.httpServer.enabled", true);/g' "$BUILDDIR/zotero/defaults/preferences/zotero.js"
perl -pi -e 's/pref\("extensions\.zotero\.connector\.enabled", false\);/pref("extensions.zotero.connector.enabled", true);/g' "$BUILDDIR/zotero/defaults/preferences/zotero.js"

# Copy icons
cp -r "$CALLDIR/assets/icons" "$BUILDDIR/zotero/chrome/icons"

# Copy application.ini and modify
cp "$CALLDIR/assets/application.ini" "$BUILDDIR/application.ini"
perl -pi -e "s/{{VERSION}}/$VERSION/" "$BUILDDIR/application.ini"
perl -pi -e "s/{{BUILDID}}/$BUILDID/" "$BUILDDIR/application.ini"

# Copy prefs.js and modify
cp "$CALLDIR/assets/prefs.js" "$BUILDDIR/zotero/defaults/preferences"
perl -pi -e 's/pref\("app\.update\.channel", "[^"]*"\);/pref\("app\.update\.channel", "'"$UPDATE_CHANNEL"'");/' "$BUILDDIR/zotero/defaults/preferences/prefs.js"
perl -pi -e 's/%GECKO_VERSION%/'"$GECKO_VERSION"'/g' "$BUILDDIR/zotero/defaults/preferences/prefs.js"

# Delete .DS_Store and .git
find "$BUILDDIR" -depth -type d -name .git -exec rm -rf {} \;
find "$BUILDDIR" -name .DS_Store -exec rm -f {} \;

cd "$CALLDIR"

# Mac
if [ $BUILD_MAC == 1 ]; then
	echo 'Building Zotero.app'
		
	# Set up directory structure
	APPDIR="$STAGEDIR/Zotero.app"
	rm -rf "$APPDIR"
	mkdir "$APPDIR"
	chmod 755 "$APPDIR"
	cp -r "$CALLDIR/mac/Contents" "$APPDIR"
	CONTENTSDIR="$APPDIR/Contents"
	
	# Merge xulrunner and relevant assets
	mkdir "$CONTENTSDIR/MacOS"
	mkdir "$CONTENTSDIR/Frameworks"
	cp -a "$MAC_RUNTIME_PATH" "$CONTENTSDIR/Frameworks/XUL.framework"
	CURRENT_FRAMEWORK="$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current"
	rm "$CURRENT_FRAMEWORK"
	mv "$CONTENTSDIR/Frameworks/XUL.framework/Versions/"[1-9]* "$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current"
	cp "$CONTENTSDIR/Frameworks/XUL.framework/Versions/Current/xulrunner" "$CONTENTSDIR/MacOS/zotero"
	cp "$BUILDDIR/application.ini" "$CONTENTSDIR/Resources"
	cp "$CALLDIR/mac/Contents/Info.plist" "$CONTENTSDIR"
	
	# Modify Info.plist
	cp "$CALLDIR/mac/Contents/Info.plist" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/{{VERSION}}/$VERSION/" "$CONTENTSDIR/Info.plist"
	perl -pi -e "s/{{VERSION_NUMERIC}}/$VERSION_NUMERIC/" "$CONTENTSDIR/Info.plist"
	# Needed for "monkeypatch" Windows builds: 
	# http://www.nntp.perl.org/group/perl.perl5.porters/2010/08/msg162834.html
	rm -f "$CONTENTSDIR/Info.plist.bak"
	
	# Add components
	cp -R "$BUILDDIR/zotero/"* "$CONTENTSDIR/Resources"
	
	# Add Mac-specific Standalone assets
	cd "$CALLDIR/assets/mac"
	zip -0 -r -q "$CONTENTSDIR/Resources/chrome/zotero.jar" *
	
	# Add word processor plug-ins
	mkdir "$CONTENTSDIR/Resources/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-mac-integration" "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org"
	perl -pi -e 's/SOURCE<\/em:version>/SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/zoteroMacWordIntegration@zotero.org/install.rdf"
	perl -pi -e 's/SOURCE<\/em:version>/SA.'"$VERSION"'<\/em:version>/' "$CONTENTSDIR/Resources/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
	
	# UGLY HACK for XULRunner 9.0 builds, which require modified paths
	for lib in "$CURRENT_FRAMEWORK"/*.dylib "$CURRENT_FRAMEWORK/XUL"
	do
		for libChange in `basename "$CURRENT_FRAMEWORK"/*.dylib` "XUL"; do
			install_name_tool -change "@executable_path/$libChange" "@loader_path/$libChange" "$lib"
		done
	done
	for lib in "$CURRENT_FRAMEWORK"/components/*.dylib
	do
		for libChange in `basename "$CURRENT_FRAMEWORK"/*.dylib` "XUL"; do
			install_name_tool -change "@executable_path/$libChange" "@loader_path/../$libChange" "$lib"
		done
	done
	# Delete extraneous files
	find "$CONTENTSDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$CONTENTSDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	find "$CONTENTSDIR/Resources/extensions" -depth -type d -name build -exec rm -rf {} \;
	
	# Sign
	/usr/bin/codesign --force --sign c8a15a3bc9eaaabc112e83b2f885609e535d07f0 \
		--requirements "=designated => anchor apple generic  and identifier \"org.zotero.zotero\" and ((cert leaf[field.1.2.840.113635.100.6.1.9] exists) or ( certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists  and certificate leaf[subject.OU] = \"8LAYR367YV\" ))" \
		"$APPDIR"
	
	# Build disk image
	if [ $PACKAGE == 1 ]; then
		if [ $MAC_NATIVE == 1 ]; then
			echo 'Creating Mac installer'
			"$CALLDIR/mac/pkg-dmg" --source "$STAGEDIR/Zotero.app" \
				--target "$DISTDIR/Zotero-$VERSION.dmg" \
				--sourcefile --volname Zotero --copy "$CALLDIR/mac/DSStore:/.DS_Store" \
				--symlink /Applications:"/Drag Here to Install" > /dev/null
		else
			echo 'Not building on Mac; creating Mac distribution as a zip file'
			rm -f "$DISTDIR/Zotero_mac.zip"
			cd "$STAGEDIR" && zip -rqX "$DISTDIR/Zotero-$VERSION_mac.zip" Zotero.app
		fi
	fi
fi

# Win32
if [ $BUILD_WIN32 == 1 ]; then
	echo 'Building Zotero_win32'
	
	# Set up directory
	APPDIR="$STAGEDIR/Zotero_win32"
	mkdir "$APPDIR"
	
	# Merge xulrunner and relevant assets
	cp -R "$BUILDDIR/zotero/"* "$BUILDDIR/application.ini" "$APPDIR"
	cp -r "$WIN32_RUNTIME_PATH" "$APPDIR/xulrunner"
	
	mv "$APPDIR/xulrunner/xulrunner-stub.exe" "$APPDIR/zotero.exe"
	
	# See http://groups.google.com/group/mozilla.dev.platform/browse_thread/thread/865d353ad8d329da/3cae433f456c10ba?lnk=gst&q=xulrunner#3cae433f456c10ba
	# Remove when we ship XULRunner 14 (https://bugzilla.mozilla.org/show_bug.cgi?id=740919)
	cp "$WIN32_RUNTIME_PATH/gkmedias.dll" "$APPDIR"
	
	# Add Windows-specific Standalone assets
	cd "$CALLDIR/assets/win"
	zip -0 -r -q "$APPDIR/chrome/zotero.jar" *
	
	# Add word processor plug-ins
	mkdir "$APPDIR/extensions"
	cp -RH "$CALLDIR/modules/zotero-word-for-windows-integration" "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org"
	cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
	perl -pi -e 's/SOURCE<\/em:version>/SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org/install.rdf"
	perl -pi -e 's/SOURCE<\/em:version>/SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
	
	# Remove unnecessary dlls
	rm "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org/components/zoteroWinWordIntegration.dll"
	rm -rf "$APPDIR/extensions/zoteroWinWordIntegration@zotero.org/"components-!($GECKO_VERSION)
	
	# Delete extraneous files
	find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
	find "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
	find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
	find "$APPDIR" \( -name '*.exe' -or -name '*.dll' \) -exec chmod 755 {} \;
	
	if [ $PACKAGE == 1 ]; then
		if [ $WIN_NATIVE == 1 ]; then
			INSTALLER_PATH="$DISTDIR/Zotero-${VERSION}_setup.exe"
			
			# Add icon to xulrunner-stub
			"$CALLDIR/win/ReplaceVistaIcon/ReplaceVistaIcon.exe" "`cygpath -w \"$APPDIR/zotero.exe\"`" \
				"`cygpath -w \"$CALLDIR/assets/icons/default/main-window.ico\"`"
			
			echo 'Creating Windows installer'
			# Copy installer files
			cp -r "$CALLDIR/win/installer" "$BUILDDIR/win_installer"
			
			# Build and sign uninstaller
			"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILDDIR/win_installer/uninstaller.nsi\"`"
			mkdir "$APPDIR/uninstall"
			mv "$BUILDDIR/win_installer/helper.exe" "$APPDIR/uninstall"
			
			# Sign zotero.exe, updater, and uninstaller
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/zotero.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Updater" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/xulrunner/updater.exe\"`"
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Uninstaller" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$APPDIR/uninstall/helper.exe\"`"
			fi
			
			# Stage installer
			INSTALLERSTAGEDIR="$BUILDDIR/win_installer/staging"
			mkdir "$INSTALLERSTAGEDIR"
			cp -R "$APPDIR" "$INSTALLERSTAGEDIR/core"
			
			# Build and sign setup.exe
			perl -pi -e "s/{{VERSION}}/$VERSION/" "$BUILDDIR/win_installer/defines.nsi"
			"`cygpath -u \"$MAKENSISU\"`" /V1 "`cygpath -w \"$BUILDDIR/win_installer/installer.nsi\"`"
			mv "$BUILDDIR/win_installer/setup.exe" "$INSTALLERSTAGEDIR"
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Setup" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$INSTALLERSTAGEDIR/setup.exe\"`"
			fi
			
			# Compress application
			cd "$INSTALLERSTAGEDIR" && "`cygpath -u \"$EXE7ZIP\"`" a -r -t7z "`cygpath -w \"$BUILDDIR/app_win32.7z\"`" \
				-mx -m0=BCJ2 -m1=LZMA:d24 -m2=LZMA:d19 -m3=LZMA:d19  -mb0:1 -mb0s1:2 -mb0s2:3 > /dev/null
				
			# Compress 7zSD.sfx
			"`cygpath -u \"$UPX\"`" --best -o "`cygpath -w \"$BUILDDIR/7zSD.sfx\"`" \
				"`cygpath -w \"$CALLDIR/win/installer/7zstub/firefox/7zSD.sfx\"`" > /dev/null
			
			# Combine 7zSD.sfx and app.tag into setup.exe
			cat "$BUILDDIR/7zSD.sfx" "$CALLDIR/win/installer/app.tag" \
				"$BUILDDIR/app_win32.7z" > "$INSTALLER_PATH"
			
			# Sign Zotero_setup.exe
			if [ $SIGN == 1 ]; then
				"`cygpath -u \"$SIGNTOOL\"`" sign /a /d "Zotero Setup" \
					/du "$SIGNATURE_URL" "`cygpath -w \"$INSTALLER_PATH\"`"
			fi
			
			chmod 755 "$INSTALLER_PATH"
		else
			echo 'Not building on Windows; only building zip file'
		fi
		cd "$STAGEDIR" && zip -rqX "$DISTDIR/Zotero-${VERSION}_win32.zip" Zotero_win32
	fi
fi

# Linux
if [ $BUILD_LINUX == 1 ]; then
	for arch in "i686" "x86_64"; do
		RUNTIME_PATH=`eval echo '$LINUX_'$arch'_RUNTIME_PATH'`
		
		# Set up directory
		echo 'Building Zotero_linux-'$arch
		APPDIR="$STAGEDIR/Zotero_linux-$arch"
		rm -rf "$APPDIR"
		mkdir "$APPDIR"
		
		# Merge xulrunner and relevant assets
		cp -R "$BUILDDIR/zotero/"* "$BUILDDIR/application.ini" "$APPDIR"
		cp -r "$RUNTIME_PATH" "$APPDIR/xulrunner"
		mv "$APPDIR/xulrunner/xulrunner-stub" "$APPDIR/zotero"
		chmod 755 "$APPDIR/zotero"
	
		# Add Unix-specific Standalone assets
		cd "$CALLDIR/assets/unix"
		zip -0 -r -q "$APPDIR/chrome/zotero.jar" *
		
		# Add word processor plug-ins
		mkdir "$APPDIR/extensions"
		cp -RH "$CALLDIR/modules/zotero-libreoffice-integration" "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org"
		perl -pi -e 's/SOURCE<\/em:version>/SA.'"$VERSION"'<\/em:version>/' "$APPDIR/extensions/zoteroOpenOfficeIntegration@zotero.org/install.rdf"
		
		# Delete extraneous files
		find "$APPDIR" -depth -type d -name .git -exec rm -rf {} \;
		find "$APPDIR" \( -name .DS_Store -or -name update.rdf \) -exec rm -f {} \;
		find "$APPDIR/extensions" -depth -type d -name build -exec rm -rf {} \;
		
		# Add run-zotero.sh
		cp "$CALLDIR/linux/run-zotero.sh" "$APPDIR/run-zotero.sh"
		
		# Move icons, so that updater.png doesn't fail
		mv "$APPDIR/xulrunner/icons" "$APPDIR/icons"
		
		if [ $PACKAGE == 1 ]; then
			# Create tar
			rm -f "$DISTDIR/Zotero-${VERSION}_linux-$arch.tar.bz2"
			cd "$STAGEDIR"
			tar -cjf "$DISTDIR/Zotero-${VERSION}_linux-$arch.tar.bz2" "Zotero_linux-$arch"
		fi
	done
fi

rm -rf $BUILDDIR
