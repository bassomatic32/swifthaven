//
//  main.swift
//  seahaven
//
//  Created by Michael Bass on 2/9/24.
//

import Foundation
import ANSITerminal
import CryptoKit


extension Collection {
	/// Returns the element at the specified index if it is within bounds, otherwise nil.
	subscript (safe index: Index) -> Element? {
		return indices.contains(index) ? self[index] : nil
	}
}

let ABANDON_THRESHOLD = 50000

enum Rank: UInt8 {
	case ace = 1
	case two, three, four, five, six, seven, eight, nine, ten
	case jack, queen, king
	
	func name() -> String {
		switch self {
		case .ace:
			return "A"
		case .jack:
			return "J"
		case .queen:
			return "Q"
		case .king:
			return "K"
		default:
			return String(self.rawValue)
		}
	}
}

enum Suit: UInt8 {
	case spades, hearts, diamonds, clubs
	
	func name() -> String {
		switch self {
			case .spades: return "S"
			case .hearts: return "H"
			case .diamonds: return "D"
			case .clubs: return "C"
		}
	}
}

struct Card {
	let rank: Rank
	let suit: Suit
	
	func name() -> String { return "\(rank.name())\(suit.name()) "}
	func coloredName() -> String { 
		let text = name()
		switch suit {
			case .spades:  return  text.asBlue 
			case .hearts: return text.asRed
			case .diamonds: return text.asLightRed
			case .clubs: return text.asLightBlue
		}
	}
}

struct Tally {
	var totalGames = 0
	var winnable = 0
	var losers = 0
	var abandoned = 0
}



struct Position {
	var index: Int
	var type: StackType
}

struct Move {
	let source: Position
	let target: Position
	let extent: Int 
}
	
// Used for hashing and sorting the deck
func cardValue(card: Card?) -> UInt8 {
	if let c = card {
		return  c.suit.rawValue as UInt8 * 20 + c.rank.rawValue as UInt8
	}
	return 0
}

func cardName(card: Card?,fallback: String) -> String {
	if let c = card {
		return c.name()
	}
	return fallback
}

func cardColoredName(card: Card?,fallback: String) -> String {
	if let c = card {
		return c.coloredName()
	}
	return fallback
}

class Stack {
	var pile:[Card] = []
}

enum StackType: Int {
	case GOAL, TABLEAU, CELL
}



class Board  {
	var goals:[Stack] = []
	var cells:[Stack] = []
	var stacks:[Stack] = []


	// create a unique checksum for the boards current state. This is used to ensure we never repeat a configuration, as its
	// easy in this game to achieve the same configuration from multiple move possibilities
	// Goal configuration is not considered
	// Cells are sorted to ensure that any order of the same cards in the cells are considered to be the same configuration
	// Stacks are sorted by the bottom most card, again to remove consideration of order from the checksum
	public var checksum: Int {
		
		// get a sorted group of cells
		var cells: [UInt8] = cells.map({cardValue(card: $0.pile.last)})	// @see cardValue
		cells.sort()

		var tabs: [[UInt8]] = stacks.map({
			$0.pile.map({cardValue(card: Optional.some($0))})
		})
		// stacks.sort_by_key(|k| if k.len() == 0 { 0 } else { k[0] });
		tabs.sort(by: {
			let v1 = if $0.count == 0 {UInt8(0)} else {$0[0]}
			let v2 = if $1.count == 0 {UInt8(0)} else {$1[0]}
			return v1 <= v2
		})
		

		if #available(macOS 10.15, *) {
			var hasher = SHA256()
			for tabStack: [UInt8] in tabs {
				hasher.update(data: tabStack)
				hasher.update(data: [UInt8(255)])
			}
			hasher.update(data: cells)
			let digest = hasher.finalize()
			return digest.hashValue
		} else {
			return 0
		}
		
	}


	
	// Initialize the board
	init() {
		
		var deck: [Card] = []
		for suit: UInt8 in 0...3 {
			for value:UInt8 in 1...13 {
				let card = Card(rank:Rank(rawValue: value)!,suit:Suit(rawValue: suit)!)
				deck.append(card)
			}
		}
		deck.shuffle()
		
		// init each of the 10 stacks with 5 cards each
		for _ in 1...10 {
			let stack = Stack()
			for _ in 1...5 {
				let card = deck.popLast()!
				stack.pile.append(card)
			}
			stacks.append(stack)
		}
						
		for _ in 1...4 { goals.append(Stack())}
		for _ in 1...4 { cells.append(Stack())}

		cells[0].pile.append(deck.popLast()!)
		cells[1].pile.append(deck.popLast()!)                
	}

	// you cannot create a sequence of more than 5 consecutive cards if a lower card of the same suit is higher in the stack.
	// Doing so will block that suit from ever making it to the goal, because you can only move 5 cards in sequence at once
	// e.g. with stack 2H 10H 9H 8H 7H 6H, moving the 5H on the end would cause a situation where the 2H could never be freed.
	// we can ensure this doesn't happen and reduce our possiblity tree
	func isBlockingMove(card:Card,targetStack:Stack,extentLength:Int) -> Bool {

		if targetStack.pile.count < 5 {
			return false;
		} 

		var foundLower = false
		var sequenceBroken = false
		var count = 1		
		
		
		for (i,stackCard) in targetStack.pile[1...].reversed().enumerated() {
			let pos = (targetStack.pile.count - i) - 1;
			let nextCard = targetStack.pile[pos-1];

			// keep counting the sequence until its broken
			if !sequenceBroken && stackCard.suit == nextCard.suit && stackCard.rank.rawValue == nextCard.rank.rawValue-1 {
				count += 1
			} else {
				sequenceBroken = true
			}

			if stackCard.suit == card.suit && stackCard.rank.rawValue < card.rank.rawValue {
				foundLower = true
				break // no reason to continue at this point
			}
			
			// println!("item {0} {1:?} {2:?}",i,stackCard,nextCard);
		}

		// if we found a lower card higher in the stack AND the counted sequence + extentLength ( how many cards we are moving onto the stack ) >= 5 , then its a blocking move, as it will
		// result in 6 or more cards in sequence with a lower card higher in the stack
		if foundLower && (count + extentLength) >= 5 {
			
			return true
		}

		return false
	}		

	// returns how many cards on the top of the stack are ordered ( inclusive ).  That is, there will always be at least one, unless the stack is empty
	func stackOrderedCount(stack:Stack) -> Int {
		if stack.pile.count == 0 {
			return 0
		}
		var count = 1
		for (i,stackCard) in stack.pile[1...].reversed().enumerated() {
			let pos = (stack.pile.count - i) - 1
			let nextCard = stack.pile[pos-1]
			if stackCard.suit == nextCard.suit && stackCard.rank.rawValue == nextCard.rank.rawValue-1 {
				count += 1
			} else {
				break
			}
		}

		return count
	}


	// return a collection of all cell positions that have nothing in them
	func findFreeCells() -> [Position]  {
		var freeCells: [Position] = []
		for (stackIndex,stack) in cells.enumerated() {
			if stack.pile.count == 0 {
				freeCells.append(Position(index:stackIndex,type: StackType.CELL))
			}
		}

		return freeCells;
		
	}	

	// count how many free cells there are
	func freeCellCount() -> Int  {
		let count = findFreeCells().count
		return count;
	}


	// an extent is a ordered set of cards ( starting with top most ) that is less or euqal to the number of freeCells+1
	// For example, the most basic extent is 1 card, and we don't need any free cells
	// we can move an extent of values 5,4,3 if there are 2 or more free cells
	// logic is simple:  move every card except the final one into the available free cells, move the final card to target, then move cards from cells back onto final card in new position
	// we will return the total number of cards in the extent, or 0 meaning there is no movable card
	func findExtent(stack: Stack) -> Int {
		let count = stackOrderedCount(stack: stack)
			
		if count <= (freeCellCount()+1) { return count }

		return 0

	}

	// Success if 52 cards in the goal stacks
	func isSuccess() -> Bool {
		let goalCount = goals.map({$0.pile.count}).reduce(0,{acc,c in acc+c})
		return goalCount == 52 // goal will have 52 cards if game is over
	}


	// Check to see if the stack is fully ordered
	// a stack is considered to be fully ordered if any ordered sequence from the top of the stack down is made up of more than the available free cells + 1
	// ( once you've hit 6 cards, the only place you can move the top card is to the goal.  You'll fill up the available cells trying to move the whole sequence)
	func isFullyOrdered(stack:Stack) -> Bool {
		if stack.pile.count == 0 {
			return true
		}
		let freeCells = freeCellCount()

		if !(stack.pile.count > (freeCells + 1) ) { // impossible to be fully ordered unless stack size is greater than the available free cells + 1
			return false;
		}

		let count = stackOrderedCount(stack: stack);

		if count > (freeCells+1) {
			return true;
		}

		return false
	}

	// Resolve a position into a reference to a particlar card stack
	func resolvePosition(position:Position) -> Stack {
		
		let stack = switch position.type {
			case StackType.GOAL : goals[position.index]
			case StackType.CELL : cells[position.index]
			case StackType.TABLEAU : stacks[position.index]
		}

		return stack;
	}	

	func moveCard(source: Position,target:Position) {
		let sourceStack = resolvePosition(position: source)
		let targetStack = resolvePosition(position: target)
		let card = sourceStack.pile.popLast()!
		targetStack.pile.append(card)
	}

	func isLegalMove(card:Card,target:Position,extentLength:Int) -> Bool {

		let targetStack = resolvePosition(position: target)
		if target.type == StackType.GOAL {
			//  two conditions.  The card is an Ace, and the goal is empty
			//  -or- the target's card is the same suit, and exactly one less in card value
			if targetStack.pile.count == 0 {
				return (card.rank == Rank.ace)				
			}
			// check if card value is same suit and exactly +1 in value
			let targetCard = targetStack.pile.last!
			return targetCard.suit == card.suit && targetCard.rank.rawValue == (card.rank.rawValue-1)
		}

		if target.type == StackType.CELL {
			return targetStack.pile.count == 0 // our only requiremnt if the target is a Cell is that the stack is empty
		}

		// target must be stack, no need to check

		// empty tableau stack can only accept king
		if targetStack.pile.count == 0 {
			return card.rank == Rank.king 
		}

		// for all other TABLEAU moves, the top of the target stack must be same suit and one GREATER in value
		let targetCard = targetStack.pile.last!
		return targetCard.suit == card.suit && targetCard.rank.rawValue == (card.rank.rawValue+1) && !isBlockingMove(card: card, targetStack: targetStack, extentLength: extentLength)
	
	}

	// even though a card may have up to 3 legal moves, only one of them make sense to make in any given circumstance
	func findLegalMove(source:Position) -> Move? {

		let sourceStack = resolvePosition(position: source)
		if (sourceStack.pile.count > 0) { // cannot move anything from an empty stack
			var card = sourceStack.pile.last! // get the card at the top of th epile

			// first check, for each goal stack, if move to goal is a legal move
			for (stackIndex,_) in goals.enumerated() {
				let target = Position(index: stackIndex, type: StackType.GOAL)
				if isLegalMove(card: card, target: target, extentLength: 1) { return Move(source:source,target:target,extent:1) } 
			}

			// short-circuit here if source stack is fully ordered.  
			if source.type == StackType.TABLEAU && isFullyOrdered( stack: sourceStack) { return nil } // no reason to move fully ordered card except to goal ( see isFullyOrdered for full definition )

			var extent = 0; 
			
			if source.type == StackType.TABLEAU {
				// stack to stack moves will use an extent
				extent = findExtent(stack: sourceStack)
				if extent > 0 {
					card = sourceStack.pile[sourceStack.pile.count - extent]
				} else {
					return nil // if we found no extent from a source that is a Tableau, it means there's nothing that can be moved from that stack
				}
			}

			// consider all moves that target the Tableau, and make sure we use the 'extent' card, not the top card
			for (i,_) in stacks.enumerated() {
				let target = Position (index: i, type: StackType.TABLEAU) 
				if isLegalMove(card: card, target: target, extentLength: extent) { return Move(source: source, target: target, extent: extent) }
			}

			// only thing left is targeting free cells
			if source.type == StackType.CELL { return nil } // a card in a cell should only move to a goal or stack, which have already been considered.  Short-circuit here if our card is in a cell
			// that is, don't move from cell to cell
			
			let freeCells = findFreeCells();
			if freeCells.count > 0 && extent <= 1 {
				return Move(source: source, target: freeCells[0], extent: 1)
			}

		}

		return nil
	}


}


class Game {
	var board: Board
	var stackSize = 0
	var totalMoves = 0
	var repeatesAvoided = 0
	var boardSet: [Int: Bool] = [:]
	var tally:Tally
	var gameMoves: [Move] = []
	var abandoned = false

	init(fromTally tally: Tally) {
		board = Board()
		self.tally = tally
	}

	func registerBoard() -> Bool {
		let chk = board.checksum
		let existingBoard = boardSet[chk]
		if let _ = existingBoard {
			repeatesAvoided += 1
			return true
		}

		boardSet[chk] = true
		
		if boardSet.count > ABANDON_THRESHOLD  { // give up after a certain point
			abandoned = true;
			return true;
		}
	
		return false
	}	

	func recordMove(source:Position,target:Position,extent:Int) {
		gameMoves.append( Move(source: source, target: target, extent: extent))
	}

	func moveCard(source:Position,target:Position,extent:Int) {
		recordMove(source: source, target: target, extent: extent)
			
		board.moveCard(source: source, target: target)	
		totalMoves += 1

		if totalMoves % 5000 == 0 {
			print(title: "Playing") 
			// Thread.sleep(forTimeInterval: 0.1)
		}
	}	

	// We move an extent by moving extent-1 cards to free cells, moving the inner most card in the extent, then moving the remaining from the cells in reverse order
	// e.g. if we have an extent of values 5,4,3 moving to a target stack where top card is 6, move 3, 4 to free cells, move 5 -> target stack, then 4,3 to target stack in that order
	// this totals to (extent-1) * 2 + 1 total moves.  This amount should be used when undoing this action
	// assume there are enough free cells to do this
	func moveExtent(source:Position,target:Position,extent:Int) {
		// let sourceStack = self.resolvePosition(source);
		
		// println!("Move extent {0:?} to {1:?} extent {2:?}",source,target,extent);
		let freeCells = board.findFreeCells()

		// the number of free cells must be at least the extent-1.  That is, we can move 1 card when theres no free cells, 2 if 1 free cell, etc.
		if freeCells.count >= (extent - 1) {
			for i in 0..<(extent - 1) {
				let cellPosition = freeCells[i];
				moveCard(source: source,target: cellPosition,extent: extent);
			}
			self.moveCard(source: source,target: target,extent: extent);
			for i in (0..<(extent-1)).reversed() {
				let cellPosition = freeCells[i];
				moveCard(source: cellPosition,target: target,extent: extent);
			}

		}
	}	



	func undoLastMove() {
		if gameMoves.count > 0 {
			let gameMove = gameMoves.popLast()! // pull off the last move

			board.moveCard(source: gameMove.target, target: gameMove.source)
		} 
	}



	// Make the given move and recursively continue playing from the new configuration.
	// That is, we will make that move, then follow that line of the possibility tree recursively.  Otherwise, we fail out of the function
	func moveAndPlayOn(move:Move ) -> Bool {

		// for TABLEAU -> TABLEAU, use move extent
		if move.extent > 1 && move.source.type == StackType.TABLEAU && move.target.type == StackType.TABLEAU {
			moveExtent(source: move.source, target: move.target, extent: move.extent)
		} else {
			self.moveCard(source: move.source, target: move.target, extent: move.extent);
		}
		// we made our move, now lets do some checks before we move on

		if board.isSuccess() { return true } // check for success
		
		let repeatBoard = registerBoard();

		if !repeatBoard {  // don't continue unless move wasn't a repeat ( classic example of too many negatives:  continue if not repeated)
			let success = cycleThroughCards() // recursively attempt to solve the new board configuration
			if success { return true } // the path from this configuration succeeded, so return true
		}

		// at this point, we know that this configuration wasn't a success, it might be a repeat, or its attempt to solve from the new configuration resulted in failure
		// in either case, we undo the move we just made
		
		if move.extent > 1 {
			let totalExtentMoves = (move.extent-1)*2 + 1;  // each extent move is recorded as individual moves, so we need to back them all out individually
			// println!("Undo extent move: {:?} ",legalMove);
			for _ in 0..<totalExtentMoves  {
				// println!("Undo extent {0} totalEtentMoves {1} index {2}",legalMove.extent,totalExtentMoves,i);
				undoLastMove() 
			}
		} else { 
			// println!("Undo standard move: {:?} ",legalMove);
			self.undoLastMove() 
		}


		return false // return the fact that this did not succeed

	}	

	// our fundamental game loop.  Iterate over every Tableau and Cell stack, finding each legal move in the current configuration
	// then make that move.  This function will be called recursively from the moveAndPlanOn() to attempt to win from the new configuration
	func cycleThroughCards() -> Bool {
		stackSize += 1

		var success = false;

		var allBoardMoves : [Move] = []

		// iterate through all tableau stacks and cells, coalating the legal moves into allBoardMoves
		for stackIndex in 0..<14 { // we will resolve this index as 10 Tableau stacks and 4 cells
			var source: Position;

			// determine the source position
			if stackIndex > 3 {
				source = Position(index: stackIndex-4, type: StackType.TABLEAU)
			} else {
				source = Position(index: stackIndex, type: StackType.CELL) 
			}


			if let move =  board.findLegalMove(source: source) {
				allBoardMoves.append(move)
			}			
		}

		// allBoardMoves.sort(by: { $0.target.type.rawValue > $1.target.type.rawValue})

		// play every move recorded for this configuration.
		for lm in allBoardMoves {			
			// thread::sleep(time::Duration::from_secs(1));
			success = self.moveAndPlayOn(move: lm)
			if success { break }
		}

		self.stackSize -= 1
		return success;
	}	

	func replayGame() {
		// rewind the entire game based on the move stack
		let moveCopy = gameMoves
		
		// # undo all moves
		for _ in 0..<(moveCopy.count) {
			undoLastMove();
			print(title: "Rewinding        ");
			Thread.sleep(forTimeInterval: 0.01)
		}
		
		for m in moveCopy {
			self.moveCard(source: m.source,target: m.target,extent: m.extent)
			if m.extent <= 1 {
				self.print(title: "Replay     ") ;
				Thread.sleep(forTimeInterval: 0.1)
			}
		}

	}



	func print(title: String) {
	
		moveTo(1,1)
		write(title)
	
		let offsetY = 2
	
		// // print goals
		for (i,goalStack) in board.goals.enumerated() {
			moveTo(offsetY+1,1+(i  * 4))					
			write(cardColoredName(card: goalStack.pile.last, fallback: " - "))			
		}
		
		
		for (i,cellStack) in board.cells.enumerated() {
			moveTo(offsetY+1,30+(i  * 4));
			write(cardColoredName(card: cellStack.pile.last, fallback: " x "))						
		}
		// // find the max length of the stacks
		let maxLength = self.board.stacks.map({ $0.pile.count}).max()! + 10
	
		for row in 0..<maxLength {		
			for (col,tableStack) in board.stacks.enumerated() {
				moveTo(offsetY+3+row,1+(col*4))	
				let card = tableStack.pile[safe: row]								
				write(cardColoredName(card: card, fallback: "   "))						
			}
		}		
	
		moveTo(offsetY+2,50);
		write("Games Played \(tally.totalGames)")
		moveTo(offsetY+4,50);
		write("Winnablle: \(tally.winnable)  Losers: \(tally.losers)  Abandoned \(tally.abandoned)")
		moveTo(offsetY+6,50)
		write("Stack Size \(stackSize)")
		moveTo(offsetY+8,50)
		write("Total Moves \(totalMoves)")
		moveTo(offsetY+10,50)
		write("Unique Boards: \(boardSet.count)  Collisions: \(repeatesAvoided) ")
		
	
	}		


	
}

func main() {
	clearScreen()
	var tally = Tally()

	for _ in 0..<1000 {
		
		let game = Game(fromTally: tally)
		game.print(title: "Start")

		let success = game.cycleThroughCards()

		tally.totalGames += 1;
		if (success) { tally.winnable += 1 }
		else { tally.losers += 1 }

		if (game.abandoned) { tally.abandoned += 1 }
		game.print(title: "Finished");

		// if success {
			// game.replayGame()
		// }

	}

}



main()