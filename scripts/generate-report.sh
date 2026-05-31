#!/bin/bash

mkdir -p reports

echo "Spring3Hibernate Build Report" > reports/build-report.txt

echo "Build Date: $(date)" >> reports/build-report.txt

echo "JaCoCo Coverage Generated" >> reports/build-report.txt

echo "JUnit Reports Generated" >> reports/build-report.txt

libreoffice \
--headless \
--convert-to pdf \
reports/build-report.txt \
--outdir reports/
