#!/bin/sh


function clean(){

  rm -rf ./version_new.h
  rm -rf ./version_old.h
  rm -rf payload
  rm -rf payload_rd
  rm -rf payload_untether

  cd hook/
  make clean
  rm -rf ../prehook/payload.h
  rm -rf payload
  cd ../

  cd prehook/
  make clean
  rm -rf payload
  cd ../

  cd prehook/
  make clean
  cd ../

  cd maker
  rm -rf maker
  rm -rf payload
  rm -rf payload_rd
  rm -rf payload_untether
  cd ..

}


if [ $# -gt 1 ]; then
  echo "bad args"
  exit
fi

if [ $# == 1 ]; then
  if [ $1 == "clean" ]; then
    clean
    exit
  fi
    echo "bad args"
    exit
fi

clean

while read line
do
echo $line | grep systemVer >> ./version_new.h
echo $line | grep majorVer >> ./version_new.h
minorVer=$(echo $line | sed -n -e 's/^.*#define minorVer //p')
done < ./version.h

newVer=$(echo $minorVer \+ 1 | bc)

echo "#define minorVer "$newVer"" >> ./version_new.h

mv ./version.h ./version_old.h
mv ./version_new.h ./version.h
rm -rf ./version_old.h

cd hook/
make
xxd -i payload >../prehook/payload.h
cd ../

cd prehook/
make
cd ../

cd maker
gcc maker.c -o maker
./maker ../hook/payload ../prehook/payload payload_rd payload payload_untether
mv -v payload ..
mv -v payload_rd ..
mv -v payload_untether ..
cd ..
