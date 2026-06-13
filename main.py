import sys
from PySide6.QtWidgets import QApplication, QLabel

app = QApplication(sys.argv)
label = QLabel("Hello from PySide6")
label.show()
sys.exit(app.exec())
