#!/bin/sh
KDE4=`kde4-config --version 2> /dev/null`
KDE3=`kde-config --version 2> /dev/null`

if [ "${KDE4}" ]; then
  echo "# Execute to following commands to install kfilefactory:"
  SERVICE=`kde4-config --path services | awk -F ':' '{print $1}'`
  SERVICE="${SERVICE}ServiceMenus"
  echo "mkdir -p ${HOME}/.kde/bin"
  echo "mkdir -p ${SERVICE}"
  echo "cp kfilefactory_kde4.pl ${HOME}/.kde/bin/kfilefactory.pl"
  echo "cp kfilefactory.desktop ${SERVICE}/"
elif [ "${KDE3}" ]; then
  echo "# Execute to following commands to install kfilefactory:"
  SERVICE="${HOME}/.kde/share/apps/konqueror/servicemenus/"
  echo "mkdir -p ${HOME}/.kde/bin"
  echo "mkdir -p ${SERVICE}"
  echo "cp kfilefactory_kde3.pl ${HOME}/.kde/bin/kfilefactory.pl"
  echo "cp kfilefactory.desktop ${SERVICE}/"
else
  echo "No KDE installation found!"
  exit 2
fi

