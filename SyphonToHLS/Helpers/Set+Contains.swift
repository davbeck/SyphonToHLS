extension Set {
	subscript(contains element: Element) -> Bool {
		get {
			self.contains(element)
		}
		set {
			if newValue {
				self.insert(element)
			} else {
				self.remove(element)
			}
		}
	}
}
