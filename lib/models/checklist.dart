class ChecklistItem {
  late String title;
  late bool isChecked;
  ChecklistItem(this.title, this.isChecked);
}

class ChecklistCatagory {
  late String title;
  late List<ChecklistItem> items;
  ChecklistCatagory(this.title, this.items);

  /// Are all items checked?
  bool get isChecked {
    for (final each in items) {
      if (!each.isChecked) return false;
    }
    return true;
  }

  /// Set all items checked
  set isChecked(bool value) {
    for (final each in items) {
      each.isChecked = value;
    }
  }
}

class Checklist {
  final String name;
  final String filename;

  List<ChecklistCatagory> catagories = [];

  Checklist(this.name, this.filename);

  Checklist.fromText(this.name, this.filename, String text) {
    ChecklistCatagory curCatagory = ChecklistCatagory("default", []);
    for (String each in text.split(RegExp(r'([\n])'))) {
      each = each.trim();
      if (each.isNotEmpty) {
        if (each.startsWith("#")) {
          if (curCatagory.items.isNotEmpty) catagories.add(curCatagory);
          // New catagory
          curCatagory = ChecklistCatagory(each.substring(1), []);
        } else {
          curCatagory.items.add(ChecklistItem(each, false));
        }
      }
    }
    if (curCatagory.items.isNotEmpty) catagories.add(curCatagory);
  }

  @override
  String toString() {
    return catagories.map((cata) => "#${cata.title}\n${cata.items.map((item) => item.title).join("\n")}").join("\n\n");
  }
}
