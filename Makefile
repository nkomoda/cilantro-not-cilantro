PYTHON := .venv/bin/python

.PHONY: setup download clean-data split train data ios all

setup:            ## Create the Python venv and install dependencies
	python3 -m venv .venv
	$(PYTHON) -m pip install -q -r scripts/requirements.txt

download:         ## Fetch openly licensed food photos into data/raw/
	cd scripts && ../$(PYTHON) download_openverse.py

clean-data:       ## Normalize, de-duplicate and count images in data/raw/
	cd scripts && ../$(PYTHON) clean_dataset.py

split:            ## Build data/split/{train,test}
	cd scripts && ../$(PYTHON) split_dataset.py

train:            ## Train with Create ML -> ios/CilantroCheck/Model/CilantroClassifier.mlmodel
	swift training/train.swift

data: clean-data split

ios:              ## Generate the Xcode project (needs Xcode + `brew install xcodegen`)
	cd ios && xcodegen && open -a Xcode CilantroCheck.xcodeproj

all: data train
