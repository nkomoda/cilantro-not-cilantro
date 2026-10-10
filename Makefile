PYTHON := .venv/bin/python

.PHONY: setup download filter import clean-data split train evaluate data ios all

setup:            ## Create the Python venv and install dependencies
	python3 -m venv .venv
	$(PYTHON) -m pip install -q -r scripts/requirements.txt

download:         ## Fetch openly licensed food photos into data/raw/
	cd scripts && ../$(PYTHON) download_openverse.py
	swift scripts/filter_nonfood.swift

filter:           ## Move non-food photos (gardens, people, animals...) to data/rejected/. Optional: DRY=1
	swift scripts/filter_nonfood.swift $(if $(DRY),--dry-run,)

import:           ## Add photos exported from the app (History -> Export). Optional: ZIP=path/to/file.zip
	$(PYTHON) scripts/import_app_export.py $(if $(ZIP),"$(ZIP)",)

clean-data:       ## Normalize, de-duplicate and count images in data/raw/
	cd scripts && ../$(PYTHON) clean_dataset.py

split:            ## Build data/split/{train,test}
	cd scripts && ../$(PYTHON) split_dataset.py

train:            ## Train with Create ML -> ios/CilantroCheck/Model/CilantroClassifier.mlmodel
	swift training/train.swift

evaluate:         ## Misclassified test images and a threshold sweep. Optional: DIR=data/split/train
	swift training/evaluate.swift $(if $(DIR),"$(DIR)",)

data: clean-data split

ios:              ## Generate the Xcode project (needs Xcode + `brew install xcodegen`)
	cd ios && xcodegen && open -a Xcode CilantroCheck.xcodeproj

all: data train
