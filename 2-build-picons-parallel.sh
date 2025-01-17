#!/bin/bash

#####################
## Setup locations ##
#####################
location=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
temp=$(mktemp -d --suffix=.picons)
logfile=$(mktemp --suffix=.picons.log)

echo "$(date +'%H:%M:%S') - INFO: Log file located at: $logfile"

###########################
## Check path for spaces ##
###########################
if [[ $location == *" "* ]]; then
    echo "$(date +'%H:%M:%S') - ERROR: The path contains spaces, please move the repository to a path without spaces!"
    exit 1
fi

########################################################
## Search for required commands and exit if not found ##
########################################################
commands=( tar sed grep tr cat sort find mkdir rm cp mv ln readlink )
for i in ${commands[@]}; do
    if ! which $i &> /dev/null; then
        missingcommands="$i $missingcommands"
    fi
done
if [[ -z $missingcommands ]]; then
    echo "$(date +'%H:%M:%S') - INFO: All required commands are found!"
else
    echo "$(date +'%H:%M:%S') - ERROR: The following commands are not found: $missingcommands"
    exit 1
fi

if which ar &> /dev/null; then
    skipipk="false"
    echo "$(date +'%H:%M:%S') - INFO: Creation of ipk files enabled!"
else
    skipipk="true"
    echo "$(date +'%H:%M:%S') - WARNING: Creation of ipk files disabled! Try installing: ar (found in package: binutils)"
fi

if which xz &> /dev/null; then
    compressor="xz -0 --memlimit=40%" ; ext="xz"
    echo "$(date +'%H:%M:%S') - INFO: Using xz as compression!"
elif which bzip2 &> /dev/null; then
    compressor="bzip2 -9" ; ext="bz2"
    echo "$(date +'%H:%M:%S') - INFO: Using bzip2 as compression!"
else
    echo "$(date +'%H:%M:%S') - ERROR: No archiver has been found! Try installing: xz (or: bzip2)"
    exit 1
fi

if which pngquant &> /dev/null; then
    pngquant="pngquant"
    echo "$(date +'%H:%M:%S') - INFO: Image compression enabled!"
else
    pngquant="cat"
    echo "$(date +'%H:%M:%S') - WARNING: Image compression disabled! Try installing: pngquant"
fi

if which convert &> /dev/null; then
    echo "$(date +'%H:%M:%S') - INFO: ImageMagick was found!"
else
    echo "$(date +'%H:%M:%S') - ERROR: ImageMagick was not found! Try installing: imagemagick"
    exit 1
fi

if [[ -f $location/build-input/svgconverter.conf ]]; then
    svgconverterconf=$location/build-input/svgconverter.conf
else
    echo "$(date +'%H:%M:%S') - WARNING: No \"svgconverter.conf\" file found in \"build-input\", using default file!"
    svgconverterconf=$location/build-source/config/svgconverter.conf
fi
if which inkscape &> /dev/null && [[ $(grep -v -e '^#' -e '^$' $svgconverterconf) = "inkscape" ]]; then
    svgconverter="inkscape -w 850 --without-gui --export-area-drawing --export-png="
    echo "$(date +'%H:%M:%S') - INFO: Using inkscape as svg converter!"
elif which rsvg-convert &> /dev/null && [[ $(grep -v -e '^#' -e '^$' $svgconverterconf) = "rsvg" ]]; then
    svgconverter="rsvg-convert -w 1000 --keep-aspect-ratio --output "
    echo "$(date +'%H:%M:%S') - INFO: Using rsvg as svg converter!"
else
    echo "$(date +'%H:%M:%S') - ERROR: SVG converter: $(grep -v -e '^#' -e '^$' $svgconverterconf), was not found!"
    exit 1
fi

##############################################
## Ask the user whether to build SNP or SRP ##
##############################################
if [[ -z $1 ]]; then
    echo "Which style are you going to build?"
    select choice in "Service Reference" "Service Reference (Full)" "Service Name" "Service Name (Full)"; do
        case $choice in
            "Service Reference" ) style=srp; break;;
            "Service Reference (Full)" ) style=srp-full; break;;
            "Service Name" ) style=snp; break;;
            "Service Name (Full)" ) style=snp-full; break;;
        esac
    done
else
    style=$1
fi

#############################################
## Check if previously chosen style exists ##
#############################################
if [[ ! $style = "srp-full" ]] && [[ ! $style = "snp-full" ]]; then
    for file in $location/build-output/servicelist-*-$style.txt ; do
        if [[ ! -f $file ]]; then
            echo "$(date +'%H:%M:%S') - ERROR: No $style servicelist has been found!"
            exit 1
        fi
    done
fi

###########################################
## Cleanup binaries folder and re-create ##
###########################################
binaries=$location/build-output/binaries-$style
if [[ -d $binaries ]]; then rm -rf $binaries; fi
mkdir $binaries

##############################
## Determine version number ##
##############################
if [[ -d $location/.git ]] && which git &> /dev/null; then
    cd $location
    hash=$(git rev-parse --short HEAD)
    version=$(date --utc --date=@$(git show -s --format=%ct $hash) +'%Y-%m-%d--%H-%M-%S')
    timestamp=$(date --utc --date=@$(git show -s --format=%ct $hash) +'%Y%m%d%H%M.%S')
else
    epoch="date --utc +%s"
    version=$(date --utc --date=@$($epoch) +'%Y-%m-%d--%H-%M-%S')
    timestamp=$(date --utc --date=@$($epoch) +'%Y%m%d%H%M.%S')
fi

echo "$(date +'%H:%M:%S') - INFO: Version: $version"

#############################################
## Some basic checking of the source files ##
#############################################
if [[ $- == *i* ]]; then
    echo "$(date +'%H:%M:%S') - EXECUTING: Checking index"
    $location/resources/tools/check-index.sh $location/build-source srp
    $location/resources/tools/check-index.sh $location/build-source snp

    echo "$(date +'%H:%M:%S') - EXECUTING: Checking logos"
    $location/resources/tools/check-logos.sh $location/build-source/logos
fi

#####################
## Create symlinks ##
#####################
echo "$(date +'%H:%M:%S') - EXECUTING: Creating symlinks"
$location/resources/tools/create-symlinks.sh $location $temp $style

####################################################################
## Start the actual conversion to picons and creation of packages ##
####################################################################
logocollection=$(grep -v -e '^#' -e '^$' $temp/create-symlinks.sh | sed -e 's/^.*logos\///g' -e 's/.png.*$//g' | sort -u )
logocount=$(echo "$logocollection" | wc -l)
mkdir -p $temp/cache

if [[ -f $location/build-input/backgrounds.conf ]]; then
    backgroundsconf=$location/build-input/backgrounds.conf
else
    echo "$(date +'%H:%M:%S') - WARNING: No \"backgrounds.conf\" file found in \"build-input\", using default file!"
    backgroundsconf=$location/build-source/config/backgrounds.conf
fi

grep -v -e '^#' -e '^$' $backgroundsconf | while read lines ; do
    currentlogo=""

    OLDIFS=$IFS
    IFS=";"
    line=($lines)
    IFS=$OLDIFS

    resolution=${line[0]}
    resize=${line[1]}
    type=${line[2]}
    background=${line[3]}
    tag=$2
    packagenamenoversion=$style$tag.$resolution-$resize.$type.on.$background
    packagename=$style$tag.$resolution-$resize.$type.on.${background}_${version}

    mkdir -p $temp/package/picon/logos

    echo "$(date +'%H:%M:%S') - EXECUTING: Creating picons: $packagenamenoversion"
    jobfile=$temp/jobs
    echo JOBFILE $jobfile
    echo "">$jobfile
    echo "">${jobfile}_converts

    echo "$logocollection" | while read logoname ; do
        ((currentlogo++))
        if [[ $- == *i* ]]; then
            echo -ne "           Converting logo: $currentlogo/$logocount"\\r
        fi

        if [[ -f $location/build-source/logos/$logoname.$type.png ]] || [[ -f $location/build-source/logos/$logoname.$type.svg ]]; then
            logotype=$type
        else
            logotype=default
        fi

        echo $logoname.$logotype >> $logfile

        if [[ -f $location/build-source/logos/$logoname.$logotype.svg ]]; then
            logo=$temp/cache/$logoname.$logotype.png
            if [[ ! -f $logo ]]; then
                echo "$svgconverter$logo $location/build-source/logos/$logoname.$logotype.svg 2>> $logfile >> $logfile" >>$jobfile
            fi
        else
            logo=$location/build-source/logos/$logoname.$logotype.png
        fi

        echo "convert $location/build-source/backgrounds/$resolution/$background.png \( $logo -background none -bordercolor none -border 100 -trim -border 1% -resize $resize -gravity center -extent $resolution +repage \) -layers merge - 2>> $logfile | $pngquant - 2>> $logfile > $temp/package/picon/logos/$logoname.png">>${jobfile}_converts
    done
    cat $jobfile | parallel -j6 --bar --eta {}

    cat ${jobfile}_converts | parallel -j6 --bar --eta {}

    echo "$(date +'%H:%M:%S') - EXECUTING: Creating binary packages: $packagenamenoversion"
    $temp/create-symlinks.sh
    find $temp/package -exec touch --no-dereference -t $timestamp {} \;



    mv $temp/package/picon $temp/package/$packagename

    #tar --dereference  -cf - --exclude=logos --directory=$temp/package $packagename | $compressor 2>> $logfile > $binaries/$packagename.hardlink.tar.$ext
    tar  -cf - --directory=$temp/package $packagename | $compressor 2>> $logfile > $binaries/$packagename.symlink.tar.$ext

    find $binaries -exec touch -t $timestamp {} \;
    rm -rf $temp/package
done

######################################
## Cleanup temporary files and exit ##
######################################
if [[ -d $temp ]]; then rm -rf $temp; fi

echo "$(date +'%H:%M:%S') - INFO: Finished building $style!"
exit 0
