import json

nb = json.load(open(r"D:\Exp\UNLV\uncertainty-aware-histopathology-survival-analysis\notebooks\publication_figures.ipynb"))

for i in range(25, 33):
    ct = nb["cells"][i]["cell_type"]
    source = "".join(nb["cells"][i]["source"])
    print(f"===== Cell {i} ({ct}) =====")
    print(source)
    print()
